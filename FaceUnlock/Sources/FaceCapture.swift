import AVFoundation
import Vision
import Accelerate

struct FaceFrame {
    let embedding: [Float]
    let yaw: Double
    let pitch: Double
}
// Inference is serialized and bounded. Camera frames and embeddings never go to disk.
final class FaceCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let queue = DispatchQueue(label: "org.hanjaime.face.capture")
    let session = AVCaptureSession()
    private var lastFrame = 0.0
    private var configured = false
    private var running = false
    var receive: ((FaceFrame?) -> Void)?
    var diagnostic: ((String) -> Void)?
    var issue: ((String) -> Void)?
    private func reject(_ message: String) { diagnostic?("얼굴 확인 대기 · 아래 안내를 확인해 주세요"); issue?(message); receive?(nil) }
    func start() { queue.async { [weak self] in self?.startOnQueue() } }
    func stop() { queue.async { [weak self] in self?.running = false; self?.session.stopRunning() } }
    private func startOnQueue() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { reject("카메라 권한 또는 장치 연결을 확인해 주세요."); return }
        if !configured {
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else { reject("카메라 권한 또는 장치 연결을 확인해 주세요."); return }
            session.beginConfiguration(); session.sessionPreset = .vga640x480
            guard session.canAddInput(input) else { session.commitConfiguration(); receive?(nil); return }
            session.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(output) else { session.removeInput(input); session.commitConfiguration(); receive?(nil); return }
            session.addOutput(output)
            if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false // Recognition and pose use the original camera coordinates.
            }
            session.commitConfiguration(); configured = true
        }
        diagnostic?("카메라 연결됨 · 영상 대기")
        running = true; lastFrame = 0; session.startRunning()
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.running, self.lastFrame == 0 else { return }
            self.reject("카메라 영상이 도착하지 않습니다. 다른 카메라 앱을 닫고 다시 시도해 주세요.")
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard running, now - lastFrame >= 0.30, let pixel = CMSampleBufferGetImageBuffer(sample) else { return }
        lastFrame = now
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        do { try VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up).perform([request]) }
        catch { reject("얼굴 위치 분석에 실패했습니다. 등록을 다시 시작해 주세요."); return }
        guard let faces = request.results, faces.count == 1 else {
            reject("카메라에 한 사람의 얼굴 전체가 보이도록 맞춰 주세요."); return
        }
        guard let yaw = faces[0].yaw?.doubleValue, let pitch = faces[0].pitch?.doubleValue else {
            reject("고개 각도를 확인하지 못했습니다. 정면을 바라봐 주세요."); return
        }
        guard let vector = infer(pixel) else { return }
        diagnostic?("얼굴 특징 확인됨 · 자세 확인")
        receive?(FaceFrame(embedding: vector, yaw: yaw, pitch: pitch))
    }
    func infer(_ pixel: CVPixelBuffer, resources: URL? = Bundle.main.resourceURL) -> [Float]? {
        guard let root = resources else { reject("얼굴 분석 리소스를 찾지 못했습니다."); return nil }
        let worker = root.appendingPathComponent("HanjaIMEFaceWorker")
        let yunet = root.appendingPathComponent("yunet.onnx"), sface = root.appendingPathComponent("sface.onnx")
        guard FileManager.default.isExecutableFile(atPath: worker.path),
              FileManager.default.fileExists(atPath: yunet.path), FileManager.default.fileExists(atPath: sface.path) else { reject("얼굴 인식 구성 파일이 없습니다. 앱을 다시 설치해 주세요."); return nil }
        let sourceWidth = CVPixelBufferGetWidth(pixel), sourceHeight = CVPixelBufferGetHeight(pixel)
        guard let size = FaceInferenceSize.fitted(width: sourceWidth, height: sourceHeight),
              CVPixelBufferGetPixelFormatType(pixel) == kCVPixelFormatType_32BGRA else {
            reject("지원하지 않는 카메라 영상 형식입니다."); return nil
        }
        let width = size.width, height = size.height
        guard CVPixelBufferLockBaseAddress(pixel, .readOnly) == kCVReturnSuccess else {
            reject("카메라 영상을 읽지 못했습니다."); return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixel) else { reject("카메라 영상이 비어 있습니다."); return nil }
        var pixels = Data(count: width * height * 4)
        defer { pixels.resetBytes(in: 0..<pixels.count) }
        let error = pixels.withUnsafeMutableBytes { bytes -> vImage_Error in
            var source = vImage_Buffer(data: base, height: vImagePixelCount(sourceHeight), width: vImagePixelCount(sourceWidth), rowBytes: CVPixelBufferGetBytesPerRow(pixel))
            var target = vImage_Buffer(data: bytes.baseAddress!, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)
            return vImageScale_ARGB8888(&source, &target, nil, vImage_Flags(kvImageHighQualityResampling))
        }
        guard error == kvImageNoError else { reject("카메라 영상 크기를 변환하지 못했습니다."); return nil }
        var frame = Data("\(width) \(height)\n".utf8)
        frame.append(pixels)
        defer { frame.resetBytes(in: 0..<frame.count) }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = worker; process.arguments = [yunet.path, sface.path]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { reject("얼굴 인식 엔진을 실행하지 못했습니다."); return nil }
        // A model failure cannot leave capture blocked on a full stdin pipe forever.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: watchdog)
        defer { watchdog.cancel(); try? input.fileHandleForWriting.close(); try? output.fileHandleForReading.close() }
        do { try input.fileHandleForWriting.write(contentsOf: frame); try input.fileHandleForWriting.close() } catch { process.terminate(); reject("카메라 영상을 분석 엔진에 전달하지 못했습니다."); return nil }
        let result = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { reject("얼굴 인식 엔진이 종료되었거나 응답 시간이 초과되었습니다."); return nil }
        switch FaceInferenceReply.decode(result) {
        case .embedding(let vector): return vector
        case .rejected(let message): reject(message); return nil
        }
    }
}
