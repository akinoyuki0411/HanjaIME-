import Foundation
@main struct InferenceReplyTests {
    static func main() throws {
        func rejection(_ object: Any) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: object)
            guard case .rejected(let message) = FaceInferenceReply.decode(data), !message.isEmpty else { fatalError("must reject") }
            return message
        }
        let noFace = try rejection(["error": "face_not_found"])
        let many = try rejection(["error": "multiple_faces"])
        let small = try rejection(["error": "face_too_small"])
        precondition(Set([noFace, many, small]).count == 3)
        _ = try rejection(["embedding": [0.0]])
        _ = try rejection(["embedding": Array(repeating: 0.0, count: 128)])
        _ = try rejection(["embedding": ["invalid"]])
        _ = try rejection(["error": "unknown"])
        for data in [Data(), Data("not json".utf8), Data(repeating: 0, count: 8192)] {
            guard case .rejected = FaceInferenceReply.decode(data) else { fatalError("invalid accepted") }
        }
        var vector = [Float](repeating: 0, count: 128); vector[0] = 1
        let valid = try JSONSerialization.data(withJSONObject: ["embedding": vector])
        guard case .embedding(let actual) = FaceInferenceReply.decode(valid), actual == vector else { fatalError("valid rejected") }
        for (w, h, expectedW, expectedH) in [(640,480,640,480), (1920,1080,640,360), (3840,2160,640,360), (1280,720,640,360), (1080,1920,270,480)] {
            let size = FaceInferenceSize.fitted(width: w, height: h)
            precondition(size?.width == expectedW && size?.height == expectedH)
        }
        precondition(FaceInferenceSize.fitted(width: 0, height: 480) == nil)
        precondition(FaceInferenceSize.fitted(width: 20000, height: 20000) == nil)
        print("Inference reply and camera sizing: 18 checks passed")
    }
}
