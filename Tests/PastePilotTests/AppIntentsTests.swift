import AppKit
import Foundation
import Testing
@testable import PastePilot

struct AppIntentsTests {
    @Test @MainActor
    func selectedItemUsesTheLastMenuBarSelection() throws {
        let dataDirectoryURL = try makeTemporaryDirectory()
        let pasteboard = NSPasteboard.withUniqueName()
        let store = ClipboardStore(
            pasteboard: pasteboard,
            dataDirectoryURL: dataDirectoryURL,
            pasteboardCaptureQueue: StubClipboardCaptureQueue(results: [])
        )
        let first = ClipboardItem(content: "First", kind: .text)
        let second = ClipboardItem(content: "Second", kind: .text)
        store.items = [first, second]

        let suiteName = "PastePilotAppIntentsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        PastePilotAppIntents.setSelectedItemID(second.id, defaults: defaults)

        #expect(PastePilotAppIntents.selectedItem(in: store, defaults: defaults)?.id == second.id)
        #expect(PastePilotAppIntents.item(at: 1, in: store)?.id == first.id)
        #expect(PastePilotAppIntents.item(at: 0, in: store) == nil)
    }

    @Test @MainActor
    func actionCatalogIncludesBuiltInAndEnabledCustomActions() {
        let customAction = CustomClipboardAction(
            title: "Wrap for API",
            template: "{\"value\": \"{{content}}\"}"
        )
        let disabledAction = CustomClipboardAction(
            title: "Disabled",
            template: "{{content}}",
            isEnabled: false
        )

        let actions = PastePilotAppIntents.actionEntities(
            customActions: [customAction, disabledAction]
        )

        #expect(actions.contains(where: { $0.id == "format-json" }))
        #expect(actions.contains(where: { $0.title == "Wrap for API" }))
        #expect(!actions.contains(where: { $0.title == "Disabled" }))
    }

    @Test @MainActor
    func namedActionResolvesOnlyWhenItCanRunForTheItem() {
        let item = ClipboardItem(content: "{\"name\": \"PastePilot\"}", kind: .json)

        #expect(
            PastePilotAppIntents.action(
                id: "format-json",
                for: item,
                customActions: []
            ) != nil
        )
        #expect(
            PastePilotAppIntents.action(
                id: "open-url",
                for: item,
                customActions: []
            ) == nil
        )
    }
}
