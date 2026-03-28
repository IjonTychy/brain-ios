import Foundation
import BrainCore
import GRDB
import os.log

// MARK: - File operations

final class FileReadHandler: ActionHandler, Sendable {
    let type = "file.read"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let path = properties["path"]?.stringValue else {
            return .error("file.read: path fehlt")
        }
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return .error("file.read: Dokumente-Ordner nicht verfügbar")
        }
        let fullURL = docsDir.appendingPathComponent(path)
        let resolvedPath = fullURL.standardizedFileURL.path
        guard resolvedPath.hasPrefix(docsDir.standardizedFileURL.path) else {
            return .error("file.read: Zugriff ausserhalb der App-Sandbox nicht erlaubt")
        }
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            return .error("file.read: Datei nicht gefunden")
        }
        let data = try Data(contentsOf: fullURL)
        if let text = String(data: data, encoding: .utf8) {
            return .value(.string(text))
        }
        return .value(.string(data.base64EncodedString()))
    }
}

final class FileWriteHandler: ActionHandler, Sendable {
    let type = "file.write"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let path = properties["path"]?.stringValue,
              let content = properties["content"]?.stringValue else {
            return .error("file.write: path und content erforderlich")
        }
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return .error("file.write: Dokumente-Ordner nicht verfügbar")
        }
        let fullURL = docsDir.appendingPathComponent(path)
        let resolvedPath = fullURL.standardizedFileURL.path
        guard resolvedPath.hasPrefix(docsDir.standardizedFileURL.path) else {
            return .error("file.write: Zugriff ausserhalb der App-Sandbox nicht erlaubt")
        }
        let parentDir = fullURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try content.write(to: fullURL, atomically: true, encoding: .utf8)
        return .value(.object([
            "path": .string(path),
            "size": .int(content.utf8.count),
        ]))
    }
}

final class FileDeleteHandler: ActionHandler, Sendable {
    let type = "file.delete"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let path = properties["path"]?.stringValue else {
            return .error("file.delete: path fehlt")
        }
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return .error("file.delete: Dokumente-Ordner nicht verfügbar")
        }
        let fullURL = docsDir.appendingPathComponent(path)
        let resolvedPath = fullURL.standardizedFileURL.path
        guard resolvedPath.hasPrefix(docsDir.standardizedFileURL.path) else {
            return .error("file.delete: Zugriff ausserhalb der App-Sandbox nicht erlaubt")
        }
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            return .error("file.delete: Datei nicht gefunden")
        }
        try FileManager.default.removeItem(at: fullURL)
        return .success
    }
}

final class FileShareHandler: ActionHandler, Sendable {
    let type = "file.share"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        return .value(.object([
            "action": .string("file.share"),
            "status": .string("requires_ui"),
            "message": .string("Datei-Teilen muss über die UI ausgeloest werden"),
        ]))
    }
}

// MARK: - HTTP operations

final class HTTPRequestHandler: ActionHandler, Sendable {
    let type = "http.request"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let urlString = properties["url"]?.stringValue,
              let url = URL(string: urlString) else {
            return .error("http.request: url fehlt oder ungültig")
        }
        guard url.scheme?.lowercased() == "https" else {
            return .error("http.request: Nur HTTPS erlaubt")
        }

        let method = properties["method"]?.stringValue?.uppercased() ?? "GET"
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30

        if let bodyStr = properties["body"]?.stringValue {
            request.httpBody = bodyStr.data(using: .utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let bodyText = String(data: data.prefix(10_000), encoding: .utf8) ?? ""

        return .value(.object([
            "statusCode": .int(httpResponse?.statusCode ?? 0),
            "body": .string(bodyText),
        ]))
    }
}

final class HTTPDownloadHandler: ActionHandler, Sendable {
    let type = "http.download"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let urlString = properties["url"]?.stringValue,
              let url = URL(string: urlString) else {
            return .error("http.download: url fehlt oder ungültig")
        }
        guard url.scheme?.lowercased() == "https" else {
            return .error("http.download: Nur HTTPS erlaubt")
        }

        let filename = properties["filename"]?.stringValue ?? url.lastPathComponent
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return .error("http.download: Dokumente-Ordner nicht verfügbar")
        }
        let destURL = docsDir.appendingPathComponent(filename)
        let standardized = destURL.standardizedFileURL.path
        guard standardized.hasPrefix(docsDir.standardizedFileURL.path) else {
            return .actionError(code: "http.path_traversal", message: "Download-Pfad ausserhalb des erlaubten Bereichs")
        }

        let (tempURL, response) = try await URLSession.shared.download(from: url)
        let httpResponse = response as? HTTPURLResponse
        // Remove existing file if it exists
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.moveItem(at: tempURL, to: destURL)

        return .value(.object([
            "path": .string(filename),
            "statusCode": .int(httpResponse?.statusCode ?? 0),
        ]))
    }
}

// MARK: - Local storage (UserDefaults key-value)

final class StorageGetHandler: ActionHandler, Sendable {
    let type = "storage.get"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let key = properties["key"]?.stringValue else {
            return .error("storage.get: key fehlt")
        }
        if let value = UserDefaults.standard.string(forKey: "brain.storage.\(key)") {
            return .value(.string(value))
        }
        return .value(.null)
    }
}

final class StorageSetHandler: ActionHandler, Sendable {
    let type = "storage.set"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let key = properties["key"]?.stringValue else {
            return .error("storage.set: key fehlt")
        }
        let prefixedKey = "brain.storage.\(key)"
        if let value = properties["value"]?.stringValue {
            UserDefaults.standard.set(value, forKey: prefixedKey)
        } else if let intVal = properties["value"]?.intValue {
            UserDefaults.standard.set(intVal, forKey: prefixedKey)
        }
        return .success
    }
}

final class StorageDeleteHandler: ActionHandler, Sendable {
    let type = "storage.delete"

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let key = properties["key"]?.stringValue else {
            return .error("storage.delete: key fehlt")
        }
        UserDefaults.standard.removeObject(forKey: "brain.storage.\(key)")
        return .success
    }
}
