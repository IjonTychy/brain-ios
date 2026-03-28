import UIKit
import Vision
import CoreGraphics
import BrainCore

// Bridge for image analysis and vector graphics operations.
// Provides text detection with character-level bounding boxes,
// contour tracing for vectorization, and SVG generation.
// Used by: Handwriting Font, Logo Recognition, AR Text Overlay, OCR with positions.
@MainActor
final class ImageAnalysisBridge {

    // MARK: - Text Detection with Positions

    // Detect text in an image with per-character bounding boxes.
    // Unlike scan.text (which returns only the text string), this returns
    // the position and size of each detected character — useful for
    // font generation, AR overlays, translation overlays, redaction, etc.
    nonisolated func detectTextPositions(from imageData: Data, languages: [String] = ["de-DE", "en-US"]) async throws -> [DetectedCharacter] {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            throw ImageAnalysisError.invalidImage
        }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var results: [DetectedCharacter] = []
                let observations = request.results as? [VNRecognizedTextObservation] ?? []

                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let text = candidate.string

                    for (index, char) in text.enumerated() {
                        let startIndex = text.index(text.startIndex, offsetBy: index)
                        let endIndex = text.index(startIndex, offsetBy: 1)
                        let range = startIndex..<endIndex

                        if let charBox = try? candidate.boundingBox(for: range) {
                            let topLeft = charBox.topLeft
                            let bottomRight = charBox.bottomRight

                            let rect = CGRect(
                                x: topLeft.x * imageWidth,
                                y: (1.0 - topLeft.y) * imageHeight,
                                width: (bottomRight.x - topLeft.x) * imageWidth,
                                height: (topLeft.y - bottomRight.y) * imageHeight
                            )

                            results.append(DetectedCharacter(
                                character: String(char),
                                boundingBox: rect,
                                confidence: Double(observation.confidence)
                            ))
                        }
                    }
                }

                continuation.resume(returning: results)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Contour Tracing

    // Trace contours in a region of an image and return vector path data.
    // Useful for: font glyph extraction, logo vectorization, shape detection,
    // silhouette extraction, stencil generation.
    nonisolated func traceContours(from imageData: Data, region: CGRect? = nil, tolerance: CGFloat = 2.0) async throws -> VectorPaths {
        guard let fullImage = UIImage(data: imageData),
              let cgFull = fullImage.cgImage else {
            throw ImageAnalysisError.invalidImage
        }

        // Crop to region if specified, otherwise use full image
        let cropRect: CGRect
        if let region {
            cropRect = CGRect(
                x: max(0, region.origin.x - 2),
                y: max(0, region.origin.y - 2),
                width: min(region.width + 4, CGFloat(cgFull.width)),
                height: min(region.height + 4, CGFloat(cgFull.height))
            )
        } else {
            cropRect = CGRect(x: 0, y: 0, width: cgFull.width, height: cgFull.height)
        }

        guard let croppedCG = cgFull.cropping(to: cropRect) else {
            throw ImageAnalysisError.cropFailed
        }

        // Convert to grayscale
        let width = croppedCG.width
        let height = croppedCG.height
        var pixelData = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw ImageAnalysisError.contextCreationFailed
        }

        context.draw(croppedCG, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Trace contours
        let paths = traceEdges(pixels: pixelData, width: width, height: height, threshold: 128)

        // Normalize to unit coordinates (0..1000)
        let normalizedPaths = paths.map { path in
            path.map { point in
                CGPoint(
                    x: (point.x / CGFloat(width)) * 1000.0,
                    y: (1.0 - point.y / CGFloat(height)) * 1000.0
                )
            }
        }

        return VectorPaths(width: 1000, height: 1000, paths: normalizedPaths)
    }

    // MARK: - SVG Generation

    // Generate an SVG document from named vector paths.
    // Used for: font files, logo export, shape export, stencil generation.
    nonisolated func generateSVG(
        namedPaths: [String: VectorPaths],
        documentName: String = "output",
        format: SVGFormat = .font
    ) -> String {
        switch format {
        case .font:
            return generateSVGFont(namedPaths: namedPaths, fontName: documentName)
        case .shapes:
            return generateSVGShapes(namedPaths: namedPaths)
        }
    }

    // MARK: - Private: Contour Tracing

    private nonisolated func traceEdges(pixels: [UInt8], width: Int, height: Int, threshold: UInt8) -> [[CGPoint]] {
        var visited = [Bool](repeating: false, count: width * height)
        var contours: [[CGPoint]] = []

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                let isDark = pixels[idx] < threshold
                let isEdge = isDark && (
                    pixels[(y - 1) * width + x] >= threshold ||
                    pixels[(y + 1) * width + x] >= threshold ||
                    pixels[y * width + (x - 1)] >= threshold ||
                    pixels[y * width + (x + 1)] >= threshold
                )

                if isEdge && !visited[idx] {
                    var contour: [CGPoint] = []
                    var cx = x, cy = y
                    var steps = 0
                    let maxSteps = width * height / 2

                    repeat {
                        let ci = cy * width + cx
                        if visited[ci] && steps > 2 { break }
                        visited[ci] = true
                        contour.append(CGPoint(x: CGFloat(cx), y: CGFloat(cy)))

                        let neighbors: [(Int, Int)] = [
                            (cx + 1, cy), (cx + 1, cy + 1), (cx, cy + 1), (cx - 1, cy + 1),
                            (cx - 1, cy), (cx - 1, cy - 1), (cx, cy - 1), (cx + 1, cy - 1)
                        ]

                        var found = false
                        for (nx, ny) in neighbors {
                            guard nx >= 0 && nx < width && ny >= 0 && ny < height else { continue }
                            let ni = ny * width + nx
                            let dark = pixels[ni] < threshold
                            let edge = dark && (
                                (ny > 0 && pixels[(ny - 1) * width + nx] >= threshold) ||
                                (ny < height - 1 && pixels[(ny + 1) * width + nx] >= threshold) ||
                                (nx > 0 && pixels[ny * width + (nx - 1)] >= threshold) ||
                                (nx < width - 1 && pixels[ny * width + (nx + 1)] >= threshold)
                            )
                            if edge && !visited[ni] {
                                cx = nx
                                cy = ny
                                found = true
                                break
                            }
                        }

                        if !found { break }
                        steps += 1
                    } while steps < maxSteps

                    if contour.count >= 5 {
                        let simplified = simplifyPath(contour, tolerance: 2.0)
                        contours.append(simplified)
                    }
                }
            }
        }

        return contours
    }

    // Ramer-Douglas-Peucker path simplification
    private nonisolated func simplifyPath(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 3 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        rdpSimplify(points: points, start: 0, end: points.count - 1, tolerance: tolerance, keep: &keep)
        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }

    private nonisolated func rdpSimplify(points: [CGPoint], start: Int, end: Int, tolerance: CGFloat, keep: inout [Bool]) {
        guard end - start > 1 else { return }
        var maxDist: CGFloat = 0
        var maxIdx = start
        let lineStart = points[start]
        let lineEnd = points[end]

        for i in (start + 1)..<end {
            let d = perpendicularDistance(point: points[i], lineStart: lineStart, lineEnd: lineEnd)
            if d > maxDist { maxDist = d; maxIdx = i }
        }

        if maxDist > tolerance {
            keep[maxIdx] = true
            rdpSimplify(points: points, start: start, end: maxIdx, tolerance: tolerance, keep: &keep)
            rdpSimplify(points: points, start: maxIdx, end: end, tolerance: tolerance, keep: &keep)
        }
    }

    private nonisolated func perpendicularDistance(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return sqrt(pow(point.x - lineStart.x, 2) + pow(point.y - lineStart.y, 2)) }
        return abs(dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x) / len
    }

    // MARK: - Private: SVG Generation

    private nonisolated func generateSVGFont(namedPaths: [String: VectorPaths], fontName: String) -> String {
        var parts: [String] = []
        parts.append("""
        <?xml version="1.0" standalone="no"?>
        <svg xmlns="http://www.w3.org/2000/svg">
        <defs>
        <font id="\(fontName)" horiz-adv-x="1000">
        <font-face font-family="\(fontName)" units-per-em="1000" ascent="800" descent="-200" />
        <missing-glyph horiz-adv-x="500" />
        """)

        for (char, vector) in namedPaths.sorted(by: { $0.key < $1.key }) {
            let unicode = char.unicodeScalars.first.map { "&#x\(String($0.value, radix: 16));" } ?? char
            let pathData = vector.paths.map { svgPathData($0) }.joined(separator: " ")
            parts.append("<glyph unicode=\"\(unicode)\" horiz-adv-x=\"\(vector.width)\" d=\"\(pathData)\" />")
        }

        parts.append("</font></defs></svg>")
        return parts.joined(separator: "\n")
    }

    private nonisolated func generateSVGShapes(namedPaths: [String: VectorPaths]) -> String {
        var parts: [String] = []
        parts.append("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1000 1000\">")

        for (name, vector) in namedPaths.sorted(by: { $0.key < $1.key }) {
            let pathData = vector.paths.map { svgPathData($0) }.joined(separator: " ")
            parts.append("<path id=\"\(name)\" d=\"\(pathData)\" fill=\"black\" />")
        }

        parts.append("</svg>")
        return parts.joined(separator: "\n")
    }

    private nonisolated func svgPathData(_ points: [CGPoint]) -> String {
        guard let first = points.first else { return "" }
        var d = "M\(Int(first.x)) \(Int(first.y))"
        for point in points.dropFirst() {
            d += " L\(Int(point.x)) \(Int(point.y))"
        }
        d += " Z"
        return d
    }
}

// MARK: - Models

enum SVGFormat: String, Sendable {
    case font    // SVG font for text rendering
    case shapes  // SVG shapes document
}

struct DetectedCharacter: Codable, Sendable {
    let character: String
    let boundingBox: CGRect
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case character, confidence, x, y, width, height
    }

    init(character: String, boundingBox: CGRect, confidence: Double) {
        self.character = character
        self.boundingBox = boundingBox
        self.confidence = confidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        character = try c.decode(String.self, forKey: .character)
        confidence = try c.decode(Double.self, forKey: .confidence)
        let x = try c.decode(CGFloat.self, forKey: .x)
        let y = try c.decode(CGFloat.self, forKey: .y)
        let w = try c.decode(CGFloat.self, forKey: .width)
        let h = try c.decode(CGFloat.self, forKey: .height)
        boundingBox = CGRect(x: x, y: y, width: w, height: h)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(character, forKey: .character)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(boundingBox.origin.x, forKey: .x)
        try c.encode(boundingBox.origin.y, forKey: .y)
        try c.encode(boundingBox.size.width, forKey: .width)
        try c.encode(boundingBox.size.height, forKey: .height)
    }
}

struct VectorPaths: Codable, Sendable {
    let width: Int
    let height: Int
    let paths: [[CGPoint]]

    enum CodingKeys: String, CodingKey {
        case width, height, paths
    }

    init(width: Int, height: Int, paths: [[CGPoint]]) {
        self.width = width
        self.height = height
        self.paths = paths
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        let rawPaths = try c.decode([[[CGFloat]]].self, forKey: .paths)
        paths = rawPaths.map { path in
            path.compactMap { coords in
                coords.count == 2 ? CGPoint(x: coords[0], y: coords[1]) : nil
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(paths.map { $0.map { [$0.x, $0.y] } }, forKey: .paths)
    }
}

enum ImageAnalysisError: Error, LocalizedError {
    case invalidImage
    case cropFailed
    case contextCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Ungültiges Bild"
        case .cropFailed: return "Bild konnte nicht zugeschnitten werden"
        case .contextCreationFailed: return "Grafik-Kontext konnte nicht erstellt werden"
        }
    }
}

// MARK: - Action Handlers (generic names, reusable across skills)

// Detect text positions in an image (character-level bounding boxes).
// Use cases: Font generation, AR text overlay, translation overlay, redaction.
@MainActor
final class ImageDetectTextHandler: ActionHandler {
    let type = "image.detectText"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let base64 = properties["imageData"]?.stringValue,
              let data = Data(base64Encoded: base64) else {
            return .actionError(code: "image.missing_data", message: "imageData (base64) fehlt")
        }

        let bridge = await MainActor.run { ImageAnalysisBridge() }
        let results = try await bridge.detectTextPositions(from: data)

        guard !results.isEmpty else {
            return .actionError(code: "image.no_text", message: "Kein Text im Bild erkannt")
        }

        let chars = results.map { det -> ExpressionValue in
            .object([
                "character": .string(det.character),
                "x": .double(Double(det.boundingBox.origin.x)),
                "y": .double(Double(det.boundingBox.origin.y)),
                "width": .double(Double(det.boundingBox.size.width)),
                "height": .double(Double(det.boundingBox.size.height)),
                "confidence": .double(det.confidence),
            ])
        }

        return .value(.object([
            "characters": .array(chars),
            "count": .int(results.count),
            "text": .string(results.map(\.character).joined()),
        ]))
    }
}

// Trace contours in an image region and return vector path data.
// Use cases: Font vectorization, logo tracing, silhouette extraction, stencil creation.
@MainActor
final class ImageTraceContoursHandler: ActionHandler {
    let type = "image.traceContours"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let base64 = properties["imageData"]?.stringValue,
              let data = Data(base64Encoded: base64) else {
            return .actionError(code: "image.missing_data", message: "imageData (base64) fehlt")
        }

        // Optional region crop
        var region: CGRect?
        if let x = properties["x"]?.doubleValue,
           let y = properties["y"]?.doubleValue,
           let w = properties["width"]?.doubleValue,
           let h = properties["height"]?.doubleValue {
            region = CGRect(x: x, y: y, width: w, height: h)
        }

        let bridge = await MainActor.run { ImageAnalysisBridge() }
        let vector = try await bridge.traceContours(from: data, region: region)

        let pathsJSON = vector.paths.map { path -> ExpressionValue in
            .array(path.map { point -> ExpressionValue in
                .object(["x": .double(Double(point.x)), "y": .double(Double(point.y))])
            })
        }

        return .value(.object([
            "width": .int(vector.width),
            "height": .int(vector.height),
            "paths": .array(pathsJSON),
            "pathCount": .int(vector.paths.count),
        ]))
    }
}

// Generate an SVG document from named vector paths.
// Use cases: Font file generation, logo export, shape export.
@MainActor
final class SVGGenerateHandler: ActionHandler {
    let type = "svg.generate"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let name = properties["name"]?.stringValue ?? "output"
        let formatStr = properties["format"]?.stringValue ?? "font"
        let format = SVGFormat(rawValue: formatStr) ?? .font

        guard let glyphsValue = properties["paths"] else {
            return .actionError(code: "svg.missing_paths", message: "paths Dictionary fehlt")
        }

        var namedPaths: [String: VectorPaths] = [:]

        if case .object(let dict) = glyphsValue {
            for (key, value) in dict {
                if case .object(let vecDict) = value {
                    let w = vecDict["width"]?.intValue ?? 1000
                    let h = vecDict["height"]?.intValue ?? 1000
                    var paths: [[CGPoint]] = []

                    if case .array(let pathArr) = vecDict["paths"] {
                        for pathVal in pathArr {
                            if case .array(let pointArr) = pathVal {
                                let points = pointArr.compactMap { pointVal -> CGPoint? in
                                    if case .object(let p) = pointVal,
                                       let px = p["x"]?.doubleValue,
                                       let py = p["y"]?.doubleValue {
                                        return CGPoint(x: px, y: py)
                                    }
                                    return nil
                                }
                                paths.append(points)
                            }
                        }
                    }

                    namedPaths[key] = VectorPaths(width: w, height: h, paths: paths)
                }
            }
        }

        guard !namedPaths.isEmpty else {
            return .actionError(code: "svg.empty_paths", message: "Keine Pfad-Daten vorhanden")
        }

        let bridge = await MainActor.run { ImageAnalysisBridge() }
        let svg = bridge.generateSVG(namedPaths: namedPaths, documentName: name, format: format)

        // Save to Documents
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let fileName = "\(name).\(format == .font ? "svg" : "svg")"
        let fileURL = docs?.appendingPathComponent(fileName)

        if let fileURL {
            try svg.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        return .value(.object([
            "name": .string(name),
            "fileName": .string(fileName),
            "format": .string(format.rawValue),
            "glyphCount": .int(namedPaths.count),
            "path": .string(fileURL?.path ?? ""),
        ]))
    }
}
