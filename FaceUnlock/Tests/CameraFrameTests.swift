import AppKit
import AVFoundation
@main struct CameraFrameTests {
    static func main() throws {
        let resource = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let image = NSImage(contentsOfFile: CommandLine.arguments[2]), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("fixture missing") }
        let capture = FaceCapture()
        var failure = ""
        capture.issue = { failure = $0 }
        // Only the public OpenCV fixture is used. No camera session is started.
        for (w,h) in [(640,480),(1920,1080),(3840,2160)] {
            var buffer: CVPixelBuffer?
            precondition(CVPixelBufferCreate(nil,w,h,kCVPixelFormatType_32BGRA,nil,&buffer) == kCVReturnSuccess)
            let pixel = buffer!
            CVPixelBufferLockBaseAddress(pixel,[])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel),width: w,height: h,bitsPerComponent: 8,bytesPerRow: CVPixelBufferGetBytesPerRow(pixel),space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            context.setFillColor(NSColor.black.cgColor); context.fill(CGRect(x:0,y:0,width:w,height:h))
            let side = w
            context.draw(cg,in:CGRect(x:0,y:(h-side)/2,width:side,height:side))
            CVPixelBufferUnlockBaseAddress(pixel,[])
            let result = capture.infer(pixel,resources:resource)
            precondition(result.map(FacePolicy.valid) == true, "Frame \(w)x\(h) failed: \(failure)")
            print("Camera-size fixture \(w)x\(h): passed")
        }
    }
}
