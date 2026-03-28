import PencilKit
import Vision
import BrainCore

// Bridge between Action Primitives and PencilKit + Vision handwriting recognition.
// Provides pencil.recognizeText for converting handwritten drawings to text.
final class PencilBridge {

    // Convert a PencilKit drawing to text using Vision handwriting recognition.
    func recognizeText(from drawing: PKDrawing) async throws -> String {
        let scale = await MainActor.run { UIScreen.main.scale }
        let image = drawing.image(from: drawing.bounds, scale: scale)
        guard let cgImage = image.cgImage else {
            return ""
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["de-DE", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // Convert drawing data (serialized PKDrawing) to text.
    func recognizeText(from drawingData: Data) async throws -> String {
        let drawing = try PKDrawing(data: drawingData)
        return try await recognizeText(from: drawing)
    }
}

// MARK: - Action Handler

final class PencilRecognizeHandler: ActionHandler, Sendable {
    let type = "pencil.recognizeText"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let base64 = properties["drawingData"]?.stringValue,
              let data = Data(base64Encoded: base64) else {
            return .error("pencil.recognizeText: drawingData (base64) fehlt")
        }
        let bridge = PencilBridge()
        let text = try await bridge.recognizeText(from: data)
        return .value(.string(text))
    }
}
