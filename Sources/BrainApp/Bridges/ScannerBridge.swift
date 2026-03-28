import VisionKit
import Vision
import BrainCore

// Bridge between Action Primitives and VisionKit document scanner + Vision OCR.
// Provides OCR and structured extraction from any text (scanned or pasted).
@MainActor
final class ScannerBridge: NSObject {

    private var scanContinuation: CheckedContinuation<[String], Never>?

    var isAvailable: Bool {
        VNDocumentCameraViewController.isSupported
    }

    // Perform OCR on an image to extract text.
    nonisolated func recognizeText(in imageData: Data) async throws -> String {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
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
}

// MARK: - Structured Text Extraction (works on any text, not just scanned images)

/// Universal text extractor: pulls structured data from free-form text.
/// Works on OCR output, pasted email signatures, copied text, etc.
enum TextExtractor {

    // MARK: - Contact Info (business cards, email signatures, letterheads)

    static func extractContact(from text: String) -> ContactExtraction {
        var result = ContactExtraction()
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Pass 1: Extract unambiguous patterns (email, phone, URL)
        for line in lines {
            // Emails (all occurrences)
            let emailPattern = #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#
            if let regex = try? NSRegularExpression(pattern: emailPattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range, in: line) {
                result.emails.append(String(line[range]))
            }

            // Phone numbers (7+ digits with optional +, spaces, dashes, parens)
            let phonePattern = #"[\+]?[\d\s\-\(\)/]{7,}"#
            if let regex = try? NSRegularExpression(pattern: phonePattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range, in: line) {
                let phone = String(line[range]).trimmingCharacters(in: .whitespaces)
                if phone.filter({ $0.isNumber }).count >= 7 {
                    result.phones.append(phone)
                }
            }

            // URLs/Websites
            let urlPattern = #"(https?://|www\.)[^\s]+"#
            if let regex = try? NSRegularExpression(pattern: urlPattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range, in: line) {
                result.urls.append(String(line[range]))
            }

            // Postal address patterns (Swiss/German: PLZ Ort)
            let plzPattern = #"(CH-|D-|A-)?\d{4,5}\s+[A-ZÄÖÜ][a-zäöüß]+"#
            if line.range(of: plzPattern, options: .regularExpression) != nil {
                result.addresses.append(line)
            }

            // IBAN
            let ibanPattern = #"[A-Z]{2}\d{2}\s?[\d\s]{12,30}"#
            if line.range(of: ibanPattern, options: .regularExpression) != nil {
                result.iban = line.replacingOccurrences(of: " ", with: "")
            }
        }

        // Pass 2: Name heuristic — first line with 2-4 capitalized words that's not data
        let dataLines = Set(result.emails + result.phones + result.urls + result.addresses)
        for line in lines {
            if dataLines.contains(line) { continue }
            let words = line.split(separator: " ")
            if words.count >= 2 && words.count <= 4 && words.allSatisfy({ $0.first?.isUppercase == true }) {
                // Skip if it looks like a company (has suffix)
                let companySuffixes = ["GmbH", "AG", "Inc", "Ltd", "LLC", "SE", "KG", "Co.", "Corp", "SA", "Sàrl"]
                if !companySuffixes.contains(where: { line.contains($0) }) {
                    result.name = line
                    break
                }
            }
        }

        // Pass 3: Company — line with corporate suffix, or line right after name
        let companySuffixes = ["GmbH", "AG", "Inc", "Ltd", "LLC", "SE", "KG", "Co.", "Corp", "SA", "Sàrl"]
        for line in lines {
            if line == result.name { continue }
            if companySuffixes.contains(where: { line.contains($0) }) {
                result.company = line
                break
            }
        }
        if result.company == nil, let name = result.name, let idx = lines.firstIndex(of: name), idx + 1 < lines.count {
            let candidate = lines[idx + 1]
            if !dataLines.contains(candidate) {
                result.company = candidate
            }
        }

        // Pass 4: Job title — line near name that's not company/data
        if let name = result.name, let idx = lines.firstIndex(of: name) {
            let candidates = [idx > 0 ? lines[idx - 1] : nil, idx + 1 < lines.count ? lines[idx + 1] : nil].compactMap { $0 }
            for c in candidates {
                if c != result.company && !dataLines.contains(c) && c.count < 60 {
                    result.jobTitle = c
                    break
                }
            }
        }

        return result
    }

    // MARK: - Receipt / Invoice

    static func extractReceipt(from text: String) -> ReceiptExtraction {
        var result = ReceiptExtraction()
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let allText = text.lowercased()

        // Total amount: look for "total", "summe", "betrag", "gesamt" near a number
        let totalPatterns = [
            #"(?:total|summe|gesamt|betrag|netto|brutto|amount)[:\s]*(\d+[.,]\d{2})"#,
            #"(CHF|EUR|USD|€|\$)\s*(\d+[.,]\d{2})"#,
            #"(\d+[.,]\d{2})\s*(CHF|EUR|USD|€|\$)"#,
        ]
        for pattern in totalPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                // Extract the number
                for i in 1..<match.numberOfRanges {
                    if let range = Range(match.range(at: i), in: text) {
                        let val = String(text[range])
                        if val.range(of: #"\d+[.,]\d{2}"#, options: .regularExpression) != nil {
                            result.totalAmount = val.replacingOccurrences(of: ",", with: ".")
                            break
                        }
                    }
                }
                if result.totalAmount != nil { break }
            }
        }

        // Currency
        let currencies = ["CHF", "EUR", "USD", "GBP"]
        for currency in currencies {
            if allText.contains(currency.lowercased()) || text.contains(currency) {
                result.currency = currency
                break
            }
        }
        if result.currency == nil {
            if allText.contains("€") { result.currency = "EUR" }
            else if allText.contains("$") { result.currency = "USD" }
            else if allText.contains("fr.") || allText.contains("sfr") { result.currency = "CHF" }
        }

        // Date: common formats
        let datePatterns = [
            #"\d{1,2}\.\d{1,2}\.\d{2,4}"#,   // 23.03.2026
            #"\d{1,2}/\d{1,2}/\d{2,4}"#,      // 23/03/2026
            #"\d{4}-\d{2}-\d{2}"#,              // 2026-03-23
        ]
        for pattern in datePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text) {
                result.date = String(text[range])
                break
            }
        }

        // Vendor: usually the first or second line (store/company name)
        if let first = lines.first, first.count < 50 {
            result.vendor = first
        }

        // Tax (MwSt / VAT)
        let taxPatterns = [#"(?:mwst|vat|ust|mehrwertsteuer)[:\s]*(\d+[.,]\d{2})"#]
        for pattern in taxPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                result.taxAmount = String(text[range]).replacingOccurrences(of: ",", with: ".")
                break
            }
        }

        // Line items: lines with amount pattern
        let lineItemPattern = #"^(.+?)\s+(\d+[.,]\d{2})\s*$"#
        if let regex = try? NSRegularExpression(pattern: lineItemPattern, options: .anchorsMatchLines) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.prefix(20) {
                if let descRange = Range(match.range(at: 1), in: text),
                   let amtRange = Range(match.range(at: 2), in: text) {
                    let desc = String(text[descRange]).trimmingCharacters(in: .whitespaces)
                    let amt = String(text[amtRange]).replacingOccurrences(of: ",", with: ".")
                    result.lineItems.append((description: desc, amount: amt))
                }
            }
        }

        return result
    }
}

// MARK: - Extraction Result Types

struct ContactExtraction: Sendable {
    var name: String?
    var company: String?
    var jobTitle: String?
    var emails: [String] = []
    var phones: [String] = []
    var urls: [String] = []
    var addresses: [String] = []
    var iban: String?

    var isEmpty: Bool { name == nil && emails.isEmpty && phones.isEmpty }

    var givenName: String {
        guard let name else { return "" }
        let parts = name.split(separator: " ")
        return parts.count > 1 ? String(parts.dropLast().joined(separator: " ")) : name
    }

    var familyName: String {
        guard let name else { return "" }
        let parts = name.split(separator: " ")
        return parts.count > 1 ? String(parts.last!) : ""
    }

    func toExpressionValue() -> ExpressionValue {
        .object([
            "name": .string(name ?? ""),
            "givenName": .string(givenName),
            "familyName": .string(familyName),
            "company": .string(company ?? ""),
            "jobTitle": .string(jobTitle ?? ""),
            "email": .string(emails.first ?? ""),
            "emails": .array(emails.map { .string($0) }),
            "phone": .string(phones.first ?? ""),
            "phones": .array(phones.map { .string($0) }),
            "website": .string(urls.first ?? ""),
            "urls": .array(urls.map { .string($0) }),
            "address": .string(addresses.first ?? ""),
            "addresses": .array(addresses.map { .string($0) }),
            "iban": .string(iban ?? ""),
        ])
    }
}

struct ReceiptExtraction: Sendable {
    var vendor: String?
    var date: String?
    var totalAmount: String?
    var currency: String?
    var taxAmount: String?
    var lineItems: [(description: String, amount: String)] = []

    var isEmpty: Bool { totalAmount == nil && vendor == nil }

    func toExpressionValue() -> ExpressionValue {
        .object([
            "vendor": .string(vendor ?? ""),
            "date": .string(date ?? ""),
            "total": .string(totalAmount ?? ""),
            "currency": .string(currency ?? ""),
            "tax": .string(taxAmount ?? ""),
            "items": .array(lineItems.map { item in
                .object(["description": .string(item.description), "amount": .string(item.amount)])
            }),
        ])
    }
}

// MARK: - Action Handlers

final class ScanTextHandler: ActionHandler, Sendable {
    let type = "scan.text"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let base64 = properties["imageData"]?.stringValue,
              let data = Data(base64Encoded: base64) else {
            return .error("scan.text: imageData (base64) fehlt")
        }
        let bridge = await MainActor.run { ScannerBridge() }
        let text = try await bridge.recognizeText(in: data)
        return .value(.string(text))
    }
}

/// Extract structured contact info from text or image.
/// Input: text (direct) OR imageData (base64, will be OCR'd first).
/// Output: name, company, email(s), phone(s), address(es), IBAN.
/// Use cases: business cards, email signatures, letterheads, any text with contact info.
final class ExtractContactHandler: ActionHandler, Sendable {
    let type = "scan.extractContact"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let text: String
        if let directText = properties["text"]?.stringValue {
            text = directText
        } else if let base64 = properties["imageData"]?.stringValue,
                  let data = Data(base64Encoded: base64) {
            let bridge = await MainActor.run { ScannerBridge() }
            text = try await bridge.recognizeText(in: data)
        } else {
            return .error("scan.extractContact: 'text' oder 'imageData' (base64) fehlt")
        }

        let contact = TextExtractor.extractContact(from: text)
        if contact.isEmpty {
            return .error("Keine Kontaktdaten erkannt.")
        }

        var result = contact.toExpressionValue()
        // Add raw text for reference
        if case .object(var dict) = result {
            dict["rawText"] = .string(text)
            result = .object(dict)
        }
        return .value(result)
    }
}

/// Extract receipt/invoice data from text or image.
/// Input: text (direct) OR imageData (base64, will be OCR'd first).
/// Output: vendor, date, total, currency, tax, line items.
final class ExtractReceiptHandler: ActionHandler, Sendable {
    let type = "scan.extractReceipt"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let text: String
        if let directText = properties["text"]?.stringValue {
            text = directText
        } else if let base64 = properties["imageData"]?.stringValue,
                  let data = Data(base64Encoded: base64) {
            let bridge = await MainActor.run { ScannerBridge() }
            text = try await bridge.recognizeText(in: data)
        } else {
            return .error("scan.extractReceipt: 'text' oder 'imageData' (base64) fehlt")
        }

        let receipt = TextExtractor.extractReceipt(from: text)
        if receipt.isEmpty {
            return .error("Keine Quittungsdaten erkannt.")
        }

        var result = receipt.toExpressionValue()
        if case .object(var dict) = result {
            dict["rawText"] = .string(text)
            result = .object(dict)
        }
        return .value(result)
    }
}

// Keep backward compatibility
typealias ScanBusinessCardHandler = ExtractContactHandler
typealias BusinessCardResult = ContactExtraction
