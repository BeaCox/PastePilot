import Foundation

enum CustomClipboardActionScope: String, Codable, CaseIterable, Identifiable {
    case text
    case image
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text Only".localized
        case .image: "Images Only".localized
        case .all: "All Content".localized
        }
    }

    var acceptedKinds: Set<ContentKind> {
        switch self {
        case .text:
            Set(ContentKind.allCases).subtracting([.file, .image])
        case .image:
            [.image]
        case .all:
            Set(ContentKind.allCases)
        }
    }
}

struct CustomClipboardAction: Identifiable, Codable, Equatable {
    static let maximumCount = 20
    static let maximumTitleLength = 80
    static let maximumTemplateLength = 20_000
    static let maximumOutputLength = 1_000_000

    var id: UUID
    var title: String
    var template: String
    var scope: CustomClipboardActionScope
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        title: String = "New Action".localized,
        template: String = "{{content}}",
        scope: CustomClipboardActionScope = .text,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.template = template
        self.scope = scope
        self.isEnabled = isEnabled
    }

    var normalized: CustomClipboardAction? {
        let normalizedTitle = String(
            title.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Self.maximumTitleLength)
        )
        guard !normalizedTitle.isEmpty, !template.isEmpty else { return nil }
        var action = self
        action.title = normalizedTitle
        action.template = String(template.prefix(Self.maximumTemplateLength))
        return action
    }

    func renderedOutput(for item: ClipboardItem) -> String? {
        guard isEnabled,
              scope.acceptedKinds.contains(item.kind),
              let normalized else {
            return nil
        }
        return CustomActionTemplateRenderer.render(
            normalized.template,
            item: item,
            maximumLength: Self.maximumOutputLength
        )
    }

    static func normalized(_ actions: [CustomClipboardAction]) -> [CustomClipboardAction] {
        var seen: Set<UUID> = []
        return actions.prefix(maximumCount).compactMap { action in
            guard let normalized = action.normalized,
                  seen.insert(normalized.id).inserted else {
                return nil
            }
            return normalized
        }
    }
}

enum CustomActionTemplateRenderer {
    private static let urlComponentAllowedCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )
    private static let tokenExpression = try! NSRegularExpression(
        pattern: #"\{\{\s*([a-zA-Z]+)((?:\|[a-zA-Z]+)*)\s*\}\}"#
    )

    static func render(
        _ template: String,
        item: ClipboardItem,
        maximumLength: Int
    ) -> String? {
        let range = NSRange(template.startIndex..., in: template)
        let matches = tokenExpression.matches(in: template, range: range)
        var rendered = template

        for match in matches.reversed() {
            guard let tokenRange = Range(match.range(at: 1), in: template),
                  let transformsRange = Range(match.range(at: 2), in: template),
                  let fullRange = Range(match.range, in: rendered),
                  var value = value(for: String(template[tokenRange]), item: item) else {
                return nil
            }
            let transforms = template[transformsRange]
                .split(separator: "|")
                .map(String.init)
            for transform in transforms {
                guard let transformed = apply(transform, to: value) else { return nil }
                value = transformed
            }
            rendered.replaceSubrange(fullRange, with: value)
            guard rendered.count <= maximumLength else { return nil }
        }

        // Unknown or malformed placeholders are rejected instead of being copied
        // literally, which makes configuration mistakes visible and predictable.
        guard !rendered.contains("{{"), !rendered.contains("}}"), !rendered.isEmpty else {
            return nil
        }
        return rendered
    }

    private static func value(for token: String, item: ClipboardItem) -> String? {
        switch token.lowercased() {
        case "content":
            return item.hasExternalContent ? nil : item.content
        case "title":
            return item.userTitle ?? ""
        case "kind":
            return item.kind.rawValue
        case "sourceapp":
            return item.sourceAppName ?? ""
        case "ocr":
            return item.ocrText ?? ""
        case "imageurl":
            return item.imageSourceURL ?? ""
        case "imagepath":
            return item.imageOriginalPath ?? ""
        case "filepaths":
            return item.filePaths?.joined(separator: "\n") ?? ""
        case "newline":
            return "\n"
        default:
            return nil
        }
    }

    private static func apply(_ transform: String, to value: String) -> String? {
        switch transform.lowercased() {
        case "uppercase":
            value.uppercased()
        case "lowercase":
            value.lowercased()
        case "trim":
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        case "urlencode":
            value.addingPercentEncoding(
                withAllowedCharacters: urlComponentAllowedCharacters
            )
        case "jsonescape":
            jsonEscaped(value)
        default:
            nil
        }
    }

    private static func jsonEscaped(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8),
              encoded.count >= 2 else {
            return nil
        }
        return String(encoded.dropFirst().dropLast())
    }
}
