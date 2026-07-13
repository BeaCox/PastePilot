import Foundation

struct ClipboardSearchQuery: Equatable, Sendable {
    let rawValue: String
    let terms: [String]
    let kindFilters: Set<String>
    let appFilters: [String]
    let pinnedFilter: Bool?
    let hasFilters: Set<String>

    init(_ query: String) {
        rawValue = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsedTerms: [String] = []
        var parsedKindFilters = Set<String>()
        var parsedAppFilters: [String] = []
        var parsedPinnedFilter: Bool?
        var parsedHasFilters = Set<String>()

        for token in Self.tokens(from: rawValue) {
            guard let filter = Self.filter(from: token) else {
                parsedTerms.append(token)
                continue
            }

            switch filter.key {
            case "kind", "type":
                parsedKindFilters.insert(filter.value)
            case "app", "source":
                parsedAppFilters.append(filter.value)
            case "pinned":
                if let boolValue = Self.boolValue(from: filter.value) {
                    parsedPinnedFilter = boolValue
                } else {
                    parsedTerms.append(token)
                }
            case "has":
                parsedHasFilters.insert(filter.value)
            default:
                parsedTerms.append(token)
            }
        }

        terms = parsedTerms
        kindFilters = parsedKindFilters
        appFilters = parsedAppFilters
        pinnedFilter = parsedPinnedFilter
        hasFilters = parsedHasFilters
    }

    var isEmpty: Bool {
        !hasSearchTerms
            && kindFilters.isEmpty
            && appFilters.isEmpty
            && pinnedFilter == nil
            && hasFilters.isEmpty
    }

    var hasSearchTerms: Bool {
        !terms.isEmpty
    }

    var searchText: String {
        terms.joined(separator: " ")
    }

    var canUseTrigramFullTextSearch: Bool {
        hasSearchTerms && terms.allSatisfy { $0.count >= 3 }
    }

    func matches(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return terms.allSatisfy { text.localizedCaseInsensitiveContains($0) }
    }

    func matchesFilters(_ item: ClipboardItem) -> Bool {
        if !kindFilters.isEmpty {
            let candidates = kindCandidates(for: item.kind)
            let matchesKind = kindFilters.contains { filter in
                candidates.contains { candidate in
                    candidate == filter || candidate.contains(filter)
                }
            }
            guard matchesKind else { return false }
        }

        if let pinnedFilter, item.isPinned != pinnedFilter {
            return false
        }

        if !appFilters.isEmpty {
            let source = [
                item.sourceAppName,
                item.sourceBundleIdentifier
            ]
                .compactMap(\.self)
                .joined(separator: " ")
                .lowercased()
            guard appFilters.allSatisfy({ source.contains($0) }) else {
                return false
            }
        }

        if !hasFilters.isEmpty {
            for filter in hasFilters {
                switch filter {
                case "ocr":
                    guard item.ocrText?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty == false else {
                        return false
                    }
                case "image":
                    guard item.isImage else { return false }
                case "file", "files":
                    guard item.filePaths?.isEmpty == false else { return false }
                case "sensitive":
                    guard item.containsSensitiveData else { return false }
                case "title":
                    guard item.hasUserTitle else { return false }
                case "note", "notes":
                    guard item.hasUserNote else { return false }
                case "alias", "aliases":
                    guard item.hasUserAliases else { return false }
                default:
                    return false
                }
            }
        }

        return true
    }

    private static func tokens(from query: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var isQuoted = false
        var isEscaped = false

        for character in query {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }

            if character == "\"" {
                isQuoted.toggle()
                continue
            }

            if character.isWhitespace && !isQuoted {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            current.append(character)
        }

        if isEscaped {
            current.append("\\")
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func filter(from token: String) -> (key: String, value: String)? {
        guard let separator = token.firstIndex(of: ":"),
              separator > token.startIndex else {
            return nil
        }
        let key = token[..<separator]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let valueStart = token.index(after: separator)
        let value = token[valueStart...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !key.isEmpty, !value.isEmpty else { return nil }
        return (key, value)
    }

    private static func boolValue(from value: String) -> Bool? {
        switch value {
        case "1", "true", "yes", "y":
            return true
        case "0", "false", "no", "n":
            return false
        default:
            return nil
        }
    }

    private func kindCandidates(for kind: ContentKind) -> [String] {
        [
            kind.rawValue,
            kind.localizedTitle
        ]
        .map {
            $0.replacingOccurrences(of: " ", with: "")
                .lowercased()
        }
        + [
            kind.localizedTitle.lowercased()
        ]
    }
}
