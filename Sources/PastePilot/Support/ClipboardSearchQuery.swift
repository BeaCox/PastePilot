import Foundation

struct ClipboardSearchQuery: Equatable, Sendable {
    let rawValue: String
    let terms: [String]

    init(_ query: String) {
        rawValue = query.trimmingCharacters(in: .whitespacesAndNewlines)
        terms = rawValue
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    var isEmpty: Bool {
        terms.isEmpty
    }

    var canUseTrigramFullTextSearch: Bool {
        !terms.isEmpty && terms.allSatisfy { $0.count >= 3 }
    }

    func matches(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return terms.allSatisfy { text.localizedCaseInsensitiveContains($0) }
    }
}
