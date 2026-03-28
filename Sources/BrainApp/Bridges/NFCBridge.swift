import CoreNFC
import BrainCore

// Bridge between Action Primitives and CoreNFC.
// Provides nfc.read for reading NFC tags (NDEF format).
@MainActor
final class NFCBridge: NSObject, NFCNDEFReaderSessionDelegate {
    // @MainActor: NFC sessions use main thread for delegate callbacks.
    // Mutable state (continuation, session) is protected by actor isolation.

    private var readContinuation: CheckedContinuation<[NFCTagPayload], Error>?
    private var session: NFCNDEFReaderSession?

    // Check if NFC reading is available.
    var isAvailable: Bool {
        NFCNDEFReaderSession.readingAvailable
    }

    // Read NFC tag (starts scanning, returns when tag is found or cancelled).
    func readTag() async throws -> [NFCTagPayload] {
        guard isAvailable else {
            throw NFCBridgeError.notAvailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.readContinuation = continuation
            self.session = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: true)
            self.session?.alertMessage = "Halte dein iPhone an den NFC-Tag"
            self.session?.begin()
        }
    }

    // MARK: - NFCNDEFReaderSessionDelegate
    // Delegate callbacks are called on the queue specified in NFCNDEFReaderSession init (.main).
    // nonisolated required to satisfy protocol conformance in Swift 6 strict concurrency.

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        var payloads: [NFCTagPayload] = []
        for message in messages {
            for record in message.records {
                let payload = NFCTagPayload(
                    typeNameFormat: record.typeNameFormat.rawValue,
                    type: String(data: record.type, encoding: .utf8) ?? "",
                    payload: String(data: record.payload, encoding: .utf8) ?? "",
                    identifier: String(data: record.identifier, encoding: .utf8) ?? ""
                )
                payloads.append(payload)
            }
        }
        Task { @MainActor in
            readContinuation?.resume(returning: payloads)
            readContinuation = nil
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // User cancelled or timeout — not a real error
        let nfcError = error as? NFCReaderError
        if nfcError?.code == .readerSessionInvalidationErrorUserCanceled {
            Task { @MainActor in
                readContinuation?.resume(returning: [])
                readContinuation = nil
            }
        } else {
            Task { @MainActor in
                readContinuation?.resume(throwing: error)
                readContinuation = nil
            }
        }
    }
}

struct NFCTagPayload: Sendable {
    let typeNameFormat: UInt8
    let type: String
    let payload: String
    let identifier: String

    var expressionValue: ExpressionValue {
        .object([
            "type": .string(type),
            "payload": .string(payload),
            "identifier": .string(identifier),
        ])
    }
}

enum NFCBridgeError: Error, LocalizedError {
    case notAvailable

    var errorDescription: String? {
        "NFC ist auf diesem Gerät nicht verfügbar"
    }
}

// MARK: - Action Handler

@MainActor
final class NFCReadHandler: ActionHandler {
    let type = "nfc.read"
    private let bridge = NFCBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard bridge.isAvailable else {
            return .error("NFC nicht verfügbar")
        }
        let payloads = try await bridge.readTag()
        return .value(.array(payloads.map(\.expressionValue)))
    }
}

@MainActor
final class NFCWriteHandler: ActionHandler {
    let type = "nfc.write"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard NFCNDEFReaderSession.readingAvailable else {
            return .error("NFC nicht verfügbar")
        }
        guard let text = properties["text"]?.stringValue else {
            return .error("nfc.write: text fehlt")
        }
        // NFC writing requires a writable session — return instructions for UI layer
        // Full NDEF write requires NFCNDEFReaderSession with connect + writeNDEF
        _ = text
        return .value(.object([
            "action": .string("nfc.write"),
            "status": .string("requires_ui"),
            "message": .string("NFC-Schreiben muss über die UI mit Tag-Kontakt ausgeloest werden"),
        ]))
    }
}
