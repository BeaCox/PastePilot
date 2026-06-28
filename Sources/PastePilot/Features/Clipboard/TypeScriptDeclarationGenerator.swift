import Foundation

enum TypeScriptDeclarationGenerator {
    static func declaration(name: String, value: Any) -> String {
        declaration(name: name, value: value, depth: 0)
    }

    private static func declaration(name: String, value: Any, depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        if let dictionary = value as? [String: Any] {
            let fields = dictionary.keys.sorted().map { key in
                let fieldType = typeScriptType(dictionary[key] ?? NSNull(), depth: depth + 1)
                return "\(indent)  \(safeKey(key)): \(fieldType);"
            }.joined(separator: "\n")
            return "interface \(name) {\n\(fields)\n\(indent)}"
        }
        return "type \(name) = \(typeScriptType(value, depth: depth));"
    }

    private static func typeScriptType(_ value: Any, depth: Int) -> String {
        if value is NSNull { return "null" }
        if value is String { return "string" }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID()
                ? "boolean"
                : "number"
        }
        if let array = value as? [Any] {
            return arrayType(array, depth: depth)
        }
        if let dictionary = value as? [String: Any] {
            return objectType(dictionary, depth: depth)
        }
        return "unknown"
    }

    private static func arrayType(_ array: [Any], depth: Int) -> String {
        guard !array.isEmpty else { return "unknown[]" }

        let elementTypes = typeScriptTypes(for: array, depth: depth)
        let elementType = joinedTypeUnion(elementTypes)
        if elementTypes.count > 1 {
            return "(\(elementType))[]"
        }
        return "\(elementType)[]"
    }

    private static func typeScriptType(for values: [Any], depth: Int) -> String {
        joinedTypeUnion(typeScriptTypes(for: values, depth: depth))
    }

    private static func typeScriptTypes(for values: [Any], depth: Int) -> [String] {
        let hasNull = values.contains { $0 is NSNull }
        let nonNullValues = values.filter { !($0 is NSNull) }
        var types: [String] = []

        let dictionaries = nonNullValues.compactMap { $0 as? [String: Any] }
        if !dictionaries.isEmpty, dictionaries.count == nonNullValues.count {
            types.append(objectType(dictionaries, depth: depth))
        } else {
            types.append(contentsOf: nonNullValues.map { typeScriptType($0, depth: depth) })
        }

        if hasNull {
            types.append("null")
        }

        return uniqueList(types)
    }

    private static func objectType(_ dictionary: [String: Any], depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        let fields = dictionary.keys.sorted().map { key in
            "\(indent)  \(safeKey(key)): \(typeScriptType(dictionary[key] ?? NSNull(), depth: depth + 1));"
        }.joined(separator: "\n")
        return "{\n\(fields)\n\(indent)}"
    }

    private static func objectType(_ dictionaries: [[String: Any]], depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        let fields = Set(dictionaries.flatMap(\.keys)).sorted().map { key in
            let values = dictionaries.compactMap { $0[key] }
            let marker = values.count < dictionaries.count ? "?" : ""
            return "\(indent)  \(safeKey(key))\(marker): \(typeScriptType(for: values, depth: depth + 1));"
        }.joined(separator: "\n")
        return "{\n\(fields)\n\(indent)}"
    }

    private static func joinedTypeUnion(_ types: [String]) -> String {
        let uniqueTypes = uniqueList(types)
        guard !uniqueTypes.isEmpty else { return "unknown" }
        return uniqueTypes.joined(separator: " | ")
    }

    private static func uniqueList(_ types: [String]) -> [String] {
        types.reduce(into: [String]()) { result, type in
            if !result.contains(type) {
                result.append(type)
            }
        }
    }

    private static func safeKey(_ key: String) -> String {
        if key.range(of: #"^[A-Za-z_$][A-Za-z0-9_$]*$"#, options: .regularExpression) != nil {
            return key
        }
        guard let data = try? JSONEncoder().encode(key),
              let encoded = String(data: data, encoding: .utf8) else {
            return #""""#
        }
        return encoded
    }
}
