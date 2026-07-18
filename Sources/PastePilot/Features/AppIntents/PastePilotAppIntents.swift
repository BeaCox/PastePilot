import AppIntents
import AppKit
import Foundation

@MainActor
enum PastePilotAppIntents {
    static let selectedItemIDDefaultsKey = "PastePilot.appIntents.selectedItemID"

    static func store() -> ClipboardStore {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            return appDelegate.store
        }
        return ClipboardStore()
    }

    static func selectedItem(
        in store: ClipboardStore,
        defaults: UserDefaults = .standard
    ) -> ClipboardItem? {
        guard let identifier = defaults.string(forKey: selectedItemIDDefaultsKey),
              let id = UUID(uuidString: identifier),
              let item = store.items.first(where: { $0.id == id }) else {
            return store.items.first
        }
        return item
    }

    static func item(at index: Int, in store: ClipboardStore) -> ClipboardItem? {
        guard index > 0, store.items.indices.contains(index - 1) else { return nil }
        return store.items[index - 1]
    }

    static func setSelectedItemID(
        _ id: UUID?,
        defaults: UserDefaults = .standard
    ) {
        if let id {
            defaults.set(id.uuidString, forKey: selectedItemIDDefaultsKey)
        } else {
            defaults.removeObject(forKey: selectedItemIDDefaultsKey)
        }
    }

    static func actionEntities(
        customActions: [CustomClipboardAction]
    ) -> [PastePilotActionEntity] {
        let builtInActions = ClipboardActionRegistry.allDefinitions.map {
            PastePilotActionEntity(id: $0.id, title: $0.title, detail: $0.detail)
        }
        let customActionEntities = CustomClipboardAction.normalized(customActions)
            .filter(\.isEnabled)
            .map {
                PastePilotActionEntity(
                    id: "custom-\($0.id.uuidString.lowercased())",
                    title: $0.title,
                    detail: "Run a local template transform".localized
                )
            }
        return builtInActions + customActionEntities
    }

    static func action(
        id: String,
        for item: ClipboardItem,
        customActions: [CustomClipboardAction]
    ) -> ClipboardAction? {
        ClipboardActionFactory.actions(
            for: item,
            customActions: customActions
        ).first { $0.id == id }
    }
}

struct PastePilotClipboardItemEntity: AppEntity, Hashable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String

    init(
        item: ClipboardItem,
        userSensitivePatterns: [UserSensitivePattern] = []
    ) {
        id = item.id
        title = item.userTitle ?? item.kind.localizedTitle
        subtitle = TextPreview.summary(
            for: item,
            userPatterns: userSensitivePatterns
        )
    }

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Clipboard Item"
    )
    static var defaultQuery = PastePilotClipboardItemQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }
}

struct PastePilotClipboardItemQuery: EntityQuery {
    func entities(
        for identifiers: [PastePilotClipboardItemEntity.ID]
    ) async throws -> [PastePilotClipboardItemEntity] {
        await MainActor.run {
            let store = PastePilotAppIntents.store()
            let itemsByID = Dictionary(
                uniqueKeysWithValues: store.items.map {
                    ($0.id, $0)
                }
            )
            return identifiers.compactMap { id in
                itemsByID[id].map {
                    PastePilotClipboardItemEntity(
                        item: $0,
                        userSensitivePatterns: store.settings.userSensitivePatterns
                    )
                }
            }
        }
    }

    func suggestedEntities() async throws -> [PastePilotClipboardItemEntity] {
        await MainActor.run {
            let store = PastePilotAppIntents.store()
            return store.items.prefix(50).map {
                PastePilotClipboardItemEntity(
                    item: $0,
                    userSensitivePatterns: store.settings.userSensitivePatterns
                )
            }
        }
    }
}

struct PastePilotActionEntity: AppEntity, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "PastePilot Action"
    )
    static var defaultQuery = PastePilotActionQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(detail)")
    }
}

struct PastePilotActionQuery: EntityQuery {
    func entities(
        for identifiers: [PastePilotActionEntity.ID]
    ) async throws -> [PastePilotActionEntity] {
        await MainActor.run {
            let actions = PastePilotAppIntents.actionEntities(
                customActions: PastePilotAppIntents.store().settings.customClipboardActions
            )
            let actionsByID = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
            return identifiers.compactMap { actionsByID[$0] }
        }
    }

    func suggestedEntities() async throws -> [PastePilotActionEntity] {
        await MainActor.run {
            PastePilotAppIntents.actionEntities(
                customActions: PastePilotAppIntents.store().settings.customClipboardActions
            )
        }
    }
}

struct GetSelectedClipboardItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Selected Clipboard Item"
    static var description = IntentDescription(
        "Returns the item currently selected in PastePilot."
    )
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<PastePilotClipboardItemEntity> {
        let entity = try await MainActor.run {
            let store = PastePilotAppIntents.store()
            guard let item = PastePilotAppIntents.selectedItem(
                in: store
            ) else {
                throw PastePilotAppIntentError.noSelectedItem
            }
            return PastePilotClipboardItemEntity(
                item: item,
                userSensitivePatterns: store.settings.userSensitivePatterns
            )
        }
        return .result(value: entity)
    }
}

struct GetClipboardItemByIndexIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Clipboard Item by Index"
    static var description = IntentDescription(
        "Returns a PastePilot history item using its one-based index."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Index", default: 1)
    var index: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Get clipboard item \(\.$index)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<PastePilotClipboardItemEntity> {
        let entity = try await MainActor.run {
            guard index > 0 else { throw PastePilotAppIntentError.invalidIndex }
            let store = PastePilotAppIntents.store()
            guard let item = PastePilotAppIntents.item(
                at: index,
                in: store
            ) else {
                throw PastePilotAppIntentError.itemNotFound
            }
            return PastePilotClipboardItemEntity(
                item: item,
                userSensitivePatterns: store.settings.userSensitivePatterns
            )
        }
        return .result(value: entity)
    }
}

struct CopyClipboardItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Copy Clipboard Item"
    static var description = IntentDescription(
        "Copies a PastePilot history item to the system clipboard."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Item")
    var item: PastePilotClipboardItemEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Copy \(\.$item)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await MainActor.run {
            let store = PastePilotAppIntents.store()
            guard let clipboardItem = store.items.first(where: { $0.id == item.id }) else {
                throw PastePilotAppIntentError.itemNotFound
            }
            let result = ClipboardActionFactory.performResult(
                ClipboardActionFactory.copyAction(for: clipboardItem),
                using: store
            )
            guard result.didCopy else { throw PastePilotAppIntentError.copyFailed }
        }
        return .result(dialog: "Copied clipboard item")
    }
}

struct DeleteClipboardItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Delete Clipboard Item"
    static var description = IntentDescription(
        "Deletes a PastePilot history item."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Item")
    var item: PastePilotClipboardItemEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Delete \(\.$item)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await MainActor.run {
            let store = PastePilotAppIntents.store()
            guard store.items.contains(where: { $0.id == item.id }) else {
                throw PastePilotAppIntentError.itemNotFound
            }
            store.delete(item.id)
        }
        return .result(dialog: "Deleted clipboard item")
    }
}

struct ClearUnpinnedClipboardHistoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Clear Unpinned Clipboard History"
    static var description = IntentDescription(
        "Deletes all unpinned PastePilot history items."
    )
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            PastePilotAppIntents.store().clearUnpinned()
        }
        return .result(dialog: "Cleared unpinned clipboard history")
    }
}

struct RunPastePilotActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Run PastePilot Action"
    static var description = IntentDescription(
        "Runs a named PastePilot action for a clipboard history item."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Action")
    var action: PastePilotActionEntity

    @Parameter(title: "Item")
    var item: PastePilotClipboardItemEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$action) on \(\.$item)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await MainActor.run {
            let store = PastePilotAppIntents.store()
            guard let clipboardItem = store.items.first(where: { $0.id == item.id }) else {
                throw PastePilotAppIntentError.itemNotFound
            }
            guard let clipboardAction = PastePilotAppIntents.action(
                id: action.id,
                for: clipboardItem,
                customActions: store.settings.customClipboardActions
            ) else {
                throw PastePilotAppIntentError.actionUnavailable
            }
            let result = ClipboardActionFactory.performResult(clipboardAction, using: store)
            let copiesToClipboard = switch clipboardAction.outputEffect {
            case .clipboardText,
                 .clipboardItem,
                 .clipboardImage,
                 .clipboardFiles,
                 .clipboardRichText:
                true
            case .revealInFinder, .quickLook, .openURL:
                false
            }
            guard !copiesToClipboard || result.didCopy else {
                throw PastePilotAppIntentError.actionFailed
            }
        }
        return .result(dialog: "Ran PastePilot action")
    }
}

struct PastePilotShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetSelectedClipboardItemIntent(),
            phrases: ["Get selected item in \(.applicationName)"],
            shortTitle: "Get Selected Item",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: GetClipboardItemByIndexIntent(),
            phrases: ["Get item in \(.applicationName)"],
            shortTitle: "Get Item",
            systemImageName: "list.number"
        )
        AppShortcut(
            intent: CopyClipboardItemIntent(),
            phrases: ["Copy item in \(.applicationName)"],
            shortTitle: "Copy Item",
            systemImageName: "doc.on.doc"
        )
        AppShortcut(
            intent: DeleteClipboardItemIntent(),
            phrases: ["Delete item in \(.applicationName)"],
            shortTitle: "Delete Item",
            systemImageName: "trash"
        )
        AppShortcut(
            intent: ClearUnpinnedClipboardHistoryIntent(),
            phrases: ["Clear unpinned history in \(.applicationName)"],
            shortTitle: "Clear Unpinned",
            systemImageName: "trash.slash"
        )
        AppShortcut(
            intent: RunPastePilotActionIntent(),
            phrases: ["Run action in \(.applicationName)"],
            shortTitle: "Run Action",
            systemImageName: "wand.and.stars"
        )
    }
}

private enum PastePilotAppIntentError: LocalizedError {
    case noSelectedItem
    case invalidIndex
    case itemNotFound
    case copyFailed
    case actionUnavailable
    case actionFailed

    var errorDescription: String? {
        switch self {
        case .noSelectedItem:
            "No clipboard item is selected in PastePilot."
        case .invalidIndex:
            "Clipboard item indexes start at 1."
        case .itemNotFound:
            "The requested clipboard item is no longer available."
        case .copyFailed:
            "PastePilot could not copy that item."
        case .actionUnavailable:
            "That action is not available for this clipboard item."
        case .actionFailed:
            "PastePilot could not run that action."
        }
    }
}
