import Foundation
import BrainCore
import GRDB

// Resolves DataQuery declarations from a SkillDefinition into ExpressionValues.
// Each DataQuery maps to a parametrized GRDB query against an allowed table.
// Results are returned as ExpressionValue arrays for template binding.
@MainActor
struct SkillDataResolver {
    let pool: DatabasePool

    // Allowed table sources — whitelist for security.
    private static let allowedSources: Set<String> = ["entries", "tags", "knowledgeFacts", "emailCache"]

    // Allowed columns per source — whitelist to prevent data leakage.
    private static let allowedColumns: [String: Set<String>] = [
        "entries": ["id", "type", "title", "body", "status", "priority", "source", "createdAt", "updatedAt"],
        "tags": ["id", "name"],
        "knowledgeFacts": ["id", "subject", "predicate", "object", "confidence", "learnedAt"],
        "emailCache": ["id", "fromAddr", "toAddr", "subject", "snippet", "date", "folder", "isRead"],
    ]

    /// Resolve all data queries of a SkillDefinition into template variables.
    func resolve(_ definition: SkillDefinition) -> [String: ExpressionValue] {
        guard let dataQueries = definition.data else { return [:] }
        var variables: [String: ExpressionValue] = [:]
        for (key, query) in dataQueries {
            variables[key] = execute(query)
        }
        return variables
    }

    /// Execute a single DataQuery and return the result as an ExpressionValue.
    private func execute(_ query: DataQuery) -> ExpressionValue {
        guard Self.allowedSources.contains(query.source) else {
            return .array([])
        }

        let allowedCols = Self.allowedColumns[query.source] ?? []
        let tableName = query.source

        // Build parametrized SQL
        var sql = "SELECT * FROM \(tableName)"
        var arguments: StatementArguments = []

        // WHERE clauses from filter
        if let filter = query.filter, !filter.isEmpty {
            var conditions: [String] = []
            for (column, value) in filter {
                // Only allow whitelisted columns in filters
                guard allowedCols.contains(column) else { continue }
                conditions.append("\(column) = ?")
                arguments += [filterArgument(value)]
            }
            if !conditions.isEmpty {
                sql += " WHERE " + conditions.joined(separator: " AND ")
            }
        }

        // ORDER BY
        if let sort = query.sort {
            let sanitized = sanitizeSort(sort, allowedColumns: allowedCols)
            if !sanitized.isEmpty {
                sql += " ORDER BY \(sanitized)"
            }
        }

        // LIMIT
        let limit = min(query.limit ?? 100, 500)
        sql += " LIMIT \(limit)"

        // Execute
        do {
            let rows = try pool.read { db in
                try Row.fetchAll(db, sql: sql, arguments: arguments)
            }
            return rowsToExpressionValue(rows, fields: query.fields, allowedColumns: allowedCols)
        } catch {
            return .array([])
        }
    }

    /// Convert a PropertyValue filter value to a GRDB DatabaseValueConvertible.
    private func filterArgument(_ value: PropertyValue) -> any DatabaseValueConvertible {
        switch value {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        default: return ""
        }
    }

    /// Sanitize sort string to prevent SQL injection.
    /// Only allows "column ASC" or "column DESC" patterns with whitelisted columns.
    private func sanitizeSort(_ sort: String, allowedColumns: Set<String>) -> String {
        let parts = sort.split(separator: ",").compactMap { part -> String? in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            let tokens = trimmed.split(separator: " ", maxSplits: 1)
            guard let column = tokens.first else { return nil }
            let colName = String(column)
            guard allowedColumns.contains(colName) else { return nil }
            let direction = tokens.count > 1 ? String(tokens[1]).uppercased() : "ASC"
            guard direction == "ASC" || direction == "DESC" else { return nil }
            return "\(colName) \(direction)"
        }
        return parts.joined(separator: ", ")
    }

    /// Convert GRDB Rows to ExpressionValue array, optionally filtering to requested fields.
    private func rowsToExpressionValue(_ rows: [Row], fields: [String]?, allowedColumns: Set<String>) -> ExpressionValue {
        let results: [ExpressionValue] = rows.map { row in
            var obj: [String: ExpressionValue] = [:]
            let columnNames = row.columnNames
            for colName in columnNames {
                // Filter to requested fields if specified, otherwise use all allowed columns
                if let fields = fields {
                    guard fields.contains(colName) && allowedColumns.contains(colName) else { continue }
                } else {
                    guard allowedColumns.contains(colName) else { continue }
                }

                if let intVal = row[colName] as Int? {
                    obj[colName] = .string(String(intVal))
                } else if let doubleVal = row[colName] as Double? {
                    obj[colName] = .string(String(doubleVal))
                } else if let stringVal = row[colName] as String? {
                    obj[colName] = .string(stringVal)
                } else {
                    obj[colName] = .null
                }
            }
            return .object(obj)
        }
        return .array(results)
    }
}
