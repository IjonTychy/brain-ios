import UIKit
import AVFoundation
import BrainCore

// Bridge between Action Primitives and iOS Camera.
// Provides camera.capture for taking photos via UIImagePickerController.
@MainActor
final class CameraBridge: NSObject {

    private var captureContinuation: CheckedContinuation<Data?, Never>?

    // Check if camera is available on this device.
    var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    // Capture a photo using the system camera UI.
    // Returns JPEG data or nil if the user cancelled.
    func capturePhoto(from viewController: UIViewController) async -> Data? {
        await withCheckedContinuation { continuation in
            self.captureContinuation = continuation

            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = self
            picker.allowsEditing = false
            viewController.present(picker, animated: true)
        }
    }

    // Pick a photo from the photo library.
    func pickPhoto(from viewController: UIViewController) async -> Data? {
        await withCheckedContinuation { continuation in
            self.captureContinuation = continuation

            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.delegate = self
            picker.allowsEditing = false
            viewController.present(picker, animated: true)
        }
    }
}

// MARK: - UIImagePickerControllerDelegate

extension CameraBridge: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    nonisolated func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        // Extract image data before crossing isolation boundary.
        // info dict is not Sendable but we only need the image data from it.
        let image = info[.originalImage] as? UIImage
        let data = image?.jpegData(compressionQuality: 0.8)
        Task { @MainActor in
            picker.dismiss(animated: true)
            captureContinuation?.resume(returning: data)
            captureContinuation = nil
        }
    }

    nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        Task { @MainActor in
            picker.dismiss(animated: true)
            captureContinuation?.resume(returning: nil)
            captureContinuation = nil
        }
    }
}

// MARK: - Action Handlers

final class CameraCaptureHandler: ActionHandler, Sendable {
    let type = "camera.capture"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let isAvailable = await MainActor.run {
            UIImagePickerController.isSourceTypeAvailable(.camera)
        }

        guard isAvailable else {
            return .error("camera.capture: Kamera nicht verfügbar")
        }

        // Camera requires a presenting ViewController — return instructions for the UI layer
        return .value(.object([
            "action": .string("camera.capture"),
            "status": .string("requires_ui"),
            "message": .string("Kamera-Aufnahme muss über die UI ausgeloest werden"),
        ]))
    }
}

final class PhotoPickHandler: ActionHandler, Sendable {
    let type = "camera.pick"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        return .value(.object([
            "action": .string("camera.pick"),
            "status": .string("requires_ui"),
            "message": .string("Fotoauswahl muss über die UI ausgeloest werden"),
        ]))
    }
}
