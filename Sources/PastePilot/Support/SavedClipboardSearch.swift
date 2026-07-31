import Foundation

struct SavedClipboardSearch: Codable, Equatable, Identifiable, Sendable {
    static let maximumCount = 24
    static let maximumNameLength = 48
    static let maximumQueryLength = 512

    let id: UUID
    let name: String
    let query: String

    init?(
        id: UUID = UUID(),
        name: String,
        query: String
    ) {
        let normalizedName = Self.normalizedName(name)
        let normalizedQuery = Self.normalizedQuery(query)
        guard !normalizedName.isEmpty, !normalizedQuery.isEmpty else {
            return nil
        }
        self.id = id
        self.name = normalizedName
        self.query = normalizedQuery
    }

    static func normalized(
        _ searches: [SavedClipboardSearch],
        limit: Int = maximumCount
    ) -> [SavedClipboardSearch] {
        var seenNames = Set<String>()
        var normalizedSearches: [SavedClipboardSearch] = []
        normalizedSearches.reserveCapacity(min(searches.count, limit))

        for search in searches {
            guard normalizedSearches.count < limit,
                  let normalizedSearch = SavedClipboardSearch(
                      id: search.id,
                      name: search.name,
                      query: search.query
                  ) else {
                continue
            }
            let key = normalizedSearch.name.lowercased()
            guard seenNames.insert(key).inserted else { continue }
            normalizedSearches.append(normalizedSearch)
        }

        return normalizedSearches
    }

    private static func normalizedName(_ value: String) -> String {
        String(
            value
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
                .prefix(maximumNameLength)
        )
    }

    private static func normalizedQuery(_ value: String) -> String {
        String(
            value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(maximumQueryLength)
        )
    }
}

struct ClipboardSearchCollection: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case builtIn
        case saved(UUID)
    }

    let id: String
    let title: String
    let query: String
    let systemImage: String
    let kind: Kind

    static let builtInCollections: [ClipboardSearchCollection] = [
        ClipboardSearchCollection(
            id: "recent",
            title: "Recent".localized,
            query: "",
            systemImage: "clock",
            kind: .builtIn
        ),
        ClipboardSearchCollection(
            id: "pinned",
            title: "Pinned".localized,
            query: "pinned:true",
            systemImage: "pin",
            kind: .builtIn
        ),
        ClipboardSearchCollection(
            id: "protected",
            title: "Protected".localized,
            query: "has:protected",
            systemImage: "lock",
            kind: .builtIn
        ),
        ClipboardSearchCollection(
            id: "images",
            title: "Images".localized,
            query: "kind:image",
            systemImage: "photo",
            kind: .builtIn
        ),
        ClipboardSearchCollection(
            id: "files",
            title: "Files".localized,
            query: "kind:file",
            systemImage: "doc.on.doc",
            kind: .builtIn
        )
    ]

    init(
        id: String,
        title: String,
        query: String,
        systemImage: String,
        kind: Kind
    ) {
        self.id = id
        self.title = title
        self.query = query
        self.systemImage = systemImage
        self.kind = kind
    }

    init(savedSearch: SavedClipboardSearch) {
        id = "saved-\(savedSearch.id.uuidString)"
        title = savedSearch.name
        query = savedSearch.query
        systemImage = "folder"
        kind = .saved(savedSearch.id)
    }

    static func savedCollections(
        from savedSearches: [SavedClipboardSearch]
    ) -> [ClipboardSearchCollection] {
        savedSearches.map(ClipboardSearchCollection.init(savedSearch:))
    }

    static func isActiveQuery(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines) ==
            rhs.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
