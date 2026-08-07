import Foundation

enum LocalPluginMatchType: String, Codable {
    case literal
    case regularExpression
}

struct LocalPluginContentMatcher: Codable, Equatable {
    static let maximumPatternLength = 512
    static let maximumMatchedContentLength = 100_000

    let type: LocalPluginMatchType
    let pattern: String
    let caseSensitive: Bool

    init(
        type: LocalPluginMatchType,
        pattern: String,
        caseSensitive: Bool = false
    ) {
        self.type = type
        self.pattern = pattern
        self.caseSensitive = caseSensitive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(LocalPluginMatchType.self, forKey: .type)
        pattern = try container.decode(String.self, forKey: .pattern)
        caseSensitive = try container.decodeIfPresent(Bool.self, forKey: .caseSensitive)
            ?? false
    }

    func matches(_ content: String) -> Bool {
        guard !pattern.isEmpty,
              pattern.count <= Self.maximumPatternLength,
              content.count <= Self.maximumMatchedContentLength else {
            return false
        }
        switch type {
        case .literal:
            let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
            return content.range(of: pattern, options: options) != nil
        case .regularExpression:
            let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
                return false
            }
            return regex.firstMatch(
                in: content,
                range: NSRange(content.startIndex..., in: content)
            ) != nil
        }
    }

}

struct LocalActionPlugin: Identifiable, Equatable {
    let id: String
    let name: String
    let version: String
    let contentTypeNames: [String]
    let actions: [CustomClipboardAction]
    let fileName: String
}

struct LocalActionPluginCatalog {
    let plugins: [LocalActionPlugin]
    let errors: [String]

    var actions: [CustomClipboardAction] {
        plugins.flatMap(\.actions)
    }
}

enum LocalActionPluginResources {
    static let examplePluginFileName = "ExampleIssueTools.json"
    static let manifestSchemaFileName = "LocalActionPluginManifest.v1.schema.json"

    static var examplePluginURL: URL? {
        resourceURL(for: examplePluginFileName)
    }

    static var manifestSchemaURL: URL? {
        resourceURL(for: manifestSchemaFileName)
    }

    private static func resourceURL(for fileName: String) -> URL? {
        let fileURL = URL(fileURLWithPath: fileName)
        return pastePilotResourceBundle.url(
            forResource: fileURL.deletingPathExtension().lastPathComponent,
            withExtension: fileURL.pathExtension,
            subdirectory: "LocalActionPlugins"
        )
    }
}

enum LocalActionPluginLoader {
    static let maximumPluginCount = 20
    static let maximumFileByteCount = 256 * 1_024
    static let maximumContentTypeCount = 20
    static let maximumActionCount = 20

    private static let identifierExpression = try! NSRegularExpression(
        pattern: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#
    )

    static func load(
        from directoryURL: URL,
        fileManager: FileManager = .default
    ) -> LocalActionPluginCatalog {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return LocalActionPluginCatalog(plugins: [], errors: [])
        }

        var plugins: [LocalActionPlugin] = []
        var errors: [String] = []
        var identifiers: Set<String> = []
        let files = entries
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        if files.count > maximumPluginCount {
            errors.append("Only the first %d plugin files were loaded.".localized(maximumPluginCount))
        }

        for fileURL in files.prefix(maximumPluginCount) {
            do {
                let plugin = try loadPlugin(at: fileURL)
                guard identifiers.insert(plugin.id).inserted else {
                    throw ValidationError(
                        field: "identifier",
                        reason: .duplicatePluginIdentifier
                    )
                }
                plugins.append(plugin)
            } catch {
                errors.append(
                    "Could not load plugin %@: %@".localized(
                        fileURL.lastPathComponent,
                        error.localizedDescription
                    )
                )
            }
        }
        return LocalActionPluginCatalog(plugins: plugins, errors: errors)
    }

    static func loadPlugin(at fileURL: URL) throws -> LocalActionPlugin {
        guard fileURL.pathExtension.lowercased() == "json",
              !fileURL.lastPathComponent.hasPrefix(".") else {
            throw ValidationError(field: "file", reason: .invalidFile)
        }
        let values = try fileURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              values.fileSize.map({ $0 <= maximumFileByteCount }) == true else {
            throw ValidationError(field: "file", reason: .invalidFile)
        }
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: data)
        } catch let error as DecodingError {
            throw validationError(for: error)
        }
        return try validate(manifest, fileName: fileURL.lastPathComponent)
    }

    private static func validate(
        _ manifest: Manifest,
        fileName: String
    ) throws -> LocalActionPlugin {
        try require(manifest.schemaVersion == 1, field: "schemaVersion", reason: .unsupportedSchema)
        try require(
            isValidIdentifier(manifest.identifier),
            field: "identifier",
            reason: .invalidIdentifier
        )
        try validateNonblankText(manifest.name, field: "name", maximumLength: 80)
        try validateNonblankText(manifest.version, field: "version", maximumLength: 40)
        try require(
            !manifest.contentTypes.isEmpty,
            field: "contentTypes",
            reason: .emptyCollection("content type".localized)
        )
        try require(
            manifest.contentTypes.count <= maximumContentTypeCount,
            field: "contentTypes",
            reason: .tooManyItems(maximumContentTypeCount, "content types".localized)
        )
        try require(
            !manifest.actions.isEmpty,
            field: "actions",
            reason: .emptyCollection("action".localized)
        )
        try require(
            manifest.actions.count <= maximumActionCount,
            field: "actions",
            reason: .tooManyItems(maximumActionCount, "actions".localized)
        )

        var contentTypesByID: [String: ContentType] = [:]
        for (index, contentType) in manifest.contentTypes.enumerated() {
            let path = "contentTypes[\(index)]"
            try require(
                isValidIdentifier(contentType.id),
                field: "\(path).id",
                reason: .invalidIdentifier
            )
            try validateNonblankText(
                contentType.title,
                field: "\(path).title",
                maximumLength: 80
            )
            try validateMatcher(contentType.matcher, field: "\(path).matcher")
            try require(
                contentTypesByID.updateValue(contentType, forKey: contentType.id) == nil,
                field: "\(path).id",
                reason: .duplicateIdentifier
            )
        }

        var actionIDs: Set<String> = []
        let actions = try manifest.actions.enumerated().map { index, action -> CustomClipboardAction in
            let path = "actions[\(index)]"
            try require(
                isValidIdentifier(action.id),
                field: "\(path).id",
                reason: .invalidIdentifier
            )
            try require(
                actionIDs.insert(action.id).inserted,
                field: "\(path).id",
                reason: .duplicateIdentifier
            )
            try validateNonblankText(
                action.title,
                field: "\(path).title",
                maximumLength: CustomClipboardAction.maximumTitleLength
            )
            try require(
                !action.template.isEmpty,
                field: "\(path).template",
                reason: .blankValue
            )
            try require(
                action.template.count <= CustomClipboardAction.maximumTemplateLength,
                field: "\(path).template",
                reason: .tooLong(CustomClipboardAction.maximumTemplateLength)
            )
            try require(
                !action.contentTypes.isEmpty,
                field: "\(path).contentTypes",
                reason: .emptyCollection("content type reference".localized)
            )
            try require(
                action.contentTypes.count <= maximumContentTypeCount,
                field: "\(path).contentTypes",
                reason: .tooManyItems(
                    maximumContentTypeCount,
                    "content type references".localized
                )
            )
            let matchedTypes = try action.contentTypes.enumerated().map {
                referenceIndex, identifier -> ContentType in
                guard let contentType = contentTypesByID[identifier] else {
                    throw ValidationError(
                        field: "\(path).contentTypes[\(referenceIndex)]",
                        reason: .unknownContentType(identifier)
                    )
                }
                return contentType
            }
            return CustomClipboardAction(
                title: action.title,
                template: action.template,
                scope: .text,
                pluginIdentifier: manifest.identifier,
                pluginActionIdentifier: action.id,
                detail: action.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
                contentMatchers: matchedTypes.map(\.matcher)
            )
        }

        return LocalActionPlugin(
            id: manifest.identifier,
            name: manifest.name,
            version: manifest.version,
            contentTypeNames: manifest.contentTypes.map(\.title),
            actions: actions,
            fileName: fileName
        )
    }

    static func isValidIdentifier(_ value: String) -> Bool {
        identifierExpression.firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ) != nil
    }

    private static func validateNonblankText(
        _ value: String,
        field: String,
        maximumLength: Int
    ) throws {
        try require(
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            field: field,
            reason: .blankValue
        )
        try require(
            value.count <= maximumLength,
            field: field,
            reason: .tooLong(maximumLength)
        )
    }

    private static func validateMatcher(
        _ matcher: LocalPluginContentMatcher,
        field: String
    ) throws {
        try require(
            !matcher.pattern.isEmpty,
            field: "\(field).pattern",
            reason: .blankValue
        )
        try require(
            matcher.pattern.count <= LocalPluginContentMatcher.maximumPatternLength,
            field: "\(field).pattern",
            reason: .tooLong(LocalPluginContentMatcher.maximumPatternLength)
        )
        if matcher.type == .regularExpression {
            try require(
                (try? NSRegularExpression(pattern: matcher.pattern)) != nil,
                field: "\(field).pattern",
                reason: .invalidRegularExpression
            )
        }
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        field: String,
        reason: ValidationError.Reason
    ) throws {
        guard condition() else { throw ValidationError(field: field, reason: reason) }
    }

    private static func validationError(for error: DecodingError) -> ValidationError {
        switch error {
        case let .keyNotFound(key, context):
            return ValidationError(
                field: fieldPath(context.codingPath + [key]),
                reason: .missingValue
            )
        case let .typeMismatch(_, context):
            return ValidationError(
                field: fieldPath(context.codingPath),
                reason: .wrongValueType
            )
        case let .valueNotFound(_, context):
            return ValidationError(
                field: fieldPath(context.codingPath),
                reason: .missingValue
            )
        case let .dataCorrupted(context):
            return ValidationError(
                field: fieldPath(context.codingPath),
                reason: .unsupportedValue
            )
        @unknown default:
            return ValidationError(field: "JSON", reason: .unsupportedValue)
        }
    }

    private static func fieldPath(_ codingPath: [CodingKey]) -> String {
        guard !codingPath.isEmpty else { return "JSON" }
        return codingPath.reduce(into: "") { path, key in
            if let index = key.intValue {
                path += "[\(index)]"
            } else {
                if !path.isEmpty { path += "." }
                path += key.stringValue
            }
        }
    }

    private struct Manifest: Decodable {
        let schemaVersion: Int
        let identifier: String
        let name: String
        let version: String
        let contentTypes: [ContentType]
        let actions: [Action]
    }

    private struct ContentType: Decodable {
        let id: String
        let title: String
        let matcher: LocalPluginContentMatcher
    }

    private struct Action: Decodable {
        let id: String
        let title: String
        let detail: String?
        let template: String
        let contentTypes: [String]
    }

    private struct ValidationError: LocalizedError {
        enum Reason {
            case invalidFile
            case unsupportedSchema
            case invalidIdentifier
            case duplicateIdentifier
            case duplicatePluginIdentifier
            case blankValue
            case tooLong(Int)
            case emptyCollection(String)
            case tooManyItems(Int, String)
            case invalidRegularExpression
            case unknownContentType(String)
            case missingValue
            case wrongValueType
            case unsupportedValue

            var description: String {
                switch self {
                case .invalidFile:
                    "The file is not a safe regular JSON file.".localized
                case .unsupportedSchema:
                    "The value must be schema version 1.".localized
                case .invalidIdentifier:
                    "Use 1 to 128 letters, numbers, periods, underscores, or hyphens.".localized
                case .duplicateIdentifier:
                    "The identifier is duplicated in this plugin.".localized
                case .duplicatePluginIdentifier:
                    "Another plugin uses the same identifier.".localized
                case .blankValue:
                    "The value must not be blank.".localized
                case let .tooLong(limit):
                    "The value must contain at most %d characters.".localized(limit)
                case let .emptyCollection(itemName):
                    "At least one %@ is required.".localized(itemName)
                case let .tooManyItems(limit, itemName):
                    "No more than %d %@ are allowed.".localized(limit, itemName)
                case .invalidRegularExpression:
                    "The regular expression is invalid.".localized
                case let .unknownContentType(identifier):
                    "The referenced content type '%@' is not defined.".localized(identifier)
                case .missingValue:
                    "The required value is missing or null.".localized
                case .wrongValueType:
                    "The value has the wrong JSON type.".localized
                case .unsupportedValue:
                    "The value or JSON syntax is unsupported.".localized
                }
            }
        }

        let field: String
        let reason: Reason

        var errorDescription: String? {
            "Field %@: %@".localized(field, reason.description)
        }
    }
}
