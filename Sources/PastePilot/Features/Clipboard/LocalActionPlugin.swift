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

    var isValid: Bool {
        guard !pattern.isEmpty, pattern.count <= Self.maximumPatternLength else {
            return false
        }
        if type == .regularExpression {
            return (try? NSRegularExpression(pattern: pattern)) != nil
        }
        return true
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
                let values = try fileURL.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
                )
                guard values.isRegularFile == true,
                      values.isSymbolicLink != true,
                      values.fileSize.map({ $0 <= maximumFileByteCount }) == true else {
                    throw ValidationError.invalidFile
                }
                let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                let manifest = try JSONDecoder().decode(Manifest.self, from: data)
                let plugin = try validate(manifest, fileName: fileURL.lastPathComponent)
                guard identifiers.insert(plugin.id).inserted else {
                    throw ValidationError.duplicateIdentifier
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

    private static func validate(
        _ manifest: Manifest,
        fileName: String
    ) throws -> LocalActionPlugin {
        guard manifest.schemaVersion == 1,
              isValidIdentifier(manifest.identifier),
              !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.name.count <= 80,
              !manifest.version.isEmpty,
              manifest.version.count <= 40,
              !manifest.contentTypes.isEmpty,
              manifest.contentTypes.count <= maximumContentTypeCount,
              !manifest.actions.isEmpty,
              manifest.actions.count <= maximumActionCount else {
            throw ValidationError.invalidManifest
        }

        var contentTypesByID: [String: ContentType] = [:]
        for contentType in manifest.contentTypes {
            guard isValidIdentifier(contentType.id),
                  !contentType.title.isEmpty,
                  contentType.title.count <= 80,
                  contentType.matcher.isValid,
                  contentTypesByID.updateValue(contentType, forKey: contentType.id) == nil else {
                throw ValidationError.invalidContentType
            }
        }

        var actionIDs: Set<String> = []
        let actions = try manifest.actions.map { action -> CustomClipboardAction in
            guard isValidIdentifier(action.id),
                  actionIDs.insert(action.id).inserted,
                  !action.title.isEmpty,
                  action.title.count <= CustomClipboardAction.maximumTitleLength,
                  !action.template.isEmpty,
                  action.template.count <= CustomClipboardAction.maximumTemplateLength,
                  !action.contentTypes.isEmpty,
                  action.contentTypes.count <= maximumContentTypeCount else {
                throw ValidationError.invalidAction
            }
            let matchedTypes = try action.contentTypes.map { identifier -> ContentType in
                guard let contentType = contentTypesByID[identifier] else {
                    throw ValidationError.unknownContentType
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

    private static func isValidIdentifier(_ value: String) -> Bool {
        identifierExpression.firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ) != nil
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

    private enum ValidationError: LocalizedError {
        case invalidFile
        case invalidManifest
        case duplicateIdentifier
        case invalidContentType
        case invalidAction
        case unknownContentType

        var errorDescription: String? {
            switch self {
            case .invalidFile: "The file is not a safe regular JSON file.".localized
            case .invalidManifest: "The plugin manifest is invalid or unsupported.".localized
            case .duplicateIdentifier: "Another plugin uses the same identifier.".localized
            case .invalidContentType: "A content type definition is invalid.".localized
            case .invalidAction: "An action definition is invalid.".localized
            case .unknownContentType: "An action references an unknown content type.".localized
            }
        }
    }
}
