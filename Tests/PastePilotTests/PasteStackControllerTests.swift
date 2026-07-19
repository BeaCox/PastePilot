import Foundation
import Testing
@testable import PastePilot

@MainActor
@Suite(.serialized)
struct PasteStackControllerTests {
    @Test
    func pastesItemsInSelectionOrderWithConfiguredSeparator() async {
        var events: [String] = []
        let controller = PasteStackController(
            isAccessibilityGranted: { true },
            postPasteShortcut: { events.append("paste") },
            sleep: { _ in await Task.yield() },
            focusDelay: .zero,
            pasteDelay: .zero,
            interPasteDelay: .zero
        )
        let first = ClipboardItem(content: "first", kind: .text)
        let second = ClipboardItem(content: "second", kind: .text)
        let third = ClipboardItem(content: "third", kind: .text)
        controller.toggle(first.id)
        controller.toggle(second.id)
        controller.toggle(third.id)

        let result = controller.start(
            items: [first, second, third],
            separator: "\n",
            copyItem: { item in
                events.append("copy:\(item.content)")
                return true
            },
            copySeparator: { events.append("separator:\($0.debugDescription)") }
        )

        #expect(result == .started)
        await controller.waitForPendingPaste()
        #expect(events == [
            "copy:first", "paste",
            "separator:\("\n".debugDescription)", "paste",
            "copy:second", "paste",
            "separator:\("\n".debugDescription)", "paste",
            "copy:third", "paste",
        ])
        #expect(controller.completedItemCount == 3)
        #expect(controller.itemIDs.isEmpty)
        #expect(!controller.isPasting)
    }

    @Test
    func permissionIsCheckedBeforeStartingOrCopying() async {
        var didCopy = false
        var didPaste = false
        let controller = PasteStackController(
            isAccessibilityGranted: { false },
            postPasteShortcut: { didPaste = true }
        )
        let item = ClipboardItem(content: "private", kind: .text)

        let result = controller.start(
            items: [item],
            separator: "",
            copyItem: { _ in
                didCopy = true
                return true
            },
            copySeparator: { _ in }
        )

        #expect(result == .accessibilityRequired)
        await Task.yield()
        #expect(!didCopy)
        #expect(!didPaste)
        #expect(!controller.isPasting)
    }

    @Test
    func cancellingPreservesTheQueueForRetry() async {
        var pasteCount = 0
        let controller = PasteStackController(
            isAccessibilityGranted: { true },
            postPasteShortcut: { pasteCount += 1 },
            sleep: { _ in await Task.yield() },
            focusDelay: .seconds(1),
            pasteDelay: .seconds(1),
            interPasteDelay: .seconds(1)
        )
        let item = ClipboardItem(content: "later", kind: .text)
        controller.toggle(item.id)

        #expect(
            controller.start(
                items: [item],
                separator: "",
                copyItem: { _ in true },
                copySeparator: { _ in }
            ) == .started
        )
        controller.cancel()
        await Task.yield()

        #expect(!controller.isPasting)
        #expect(controller.itemIDs == [item.id])
        #expect(controller.completedItemCount == 0)
        #expect(pasteCount == 0)
    }

    @Test
    func queueOrderIsStableAndUnavailableItemsAreRemoved() {
        let controller = PasteStackController(
            isAccessibilityGranted: { true },
            postPasteShortcut: {}
        )
        let first = UUID()
        let second = UUID()
        let third = UUID()

        #expect(controller.toggle(second))
        #expect(controller.toggle(first))
        #expect(controller.toggle(third))
        #expect(controller.position(of: second) == 1)
        #expect(controller.position(of: first) == 2)
        #expect(controller.position(of: third) == 3)

        controller.retain(availableIDs: [first, third])
        #expect(controller.itemIDs == [first, third])
    }
}
