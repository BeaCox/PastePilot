import Foundation
import Testing
@testable import PastePilot

@Suite
struct CustomClipboardActionTests {
    @Test
    func templateActionsRenderLocalPlaceholdersAndTransforms() throws {
        let item = ClipboardItem(
            content: "  Hello world  ",
            kind: .text,
            sourceAppName: "Terminal",
            userTitle: "Greeting"
        )
        let action = CustomClipboardAction(
            title: "Uppercase label",
            template: "{{title}} ({{sourceApp}}): {{content|trim|uppercase}}"
        )

        #expect(
            action.renderedOutput(for: item)
                == "Greeting (Terminal): HELLO WORLD"
        )

        let generated = try #require(
            ClipboardActionFactory.actions(for: item, customActions: [action])
                .first { $0.id == "custom-\(action.id.uuidString.lowercased())" }
        )
        #expect(generated.title == "Uppercase label")
        #expect(generated.preview == "Greeting (Terminal): HELLO WORLD")
        #expect(generated.outputEffect == .clipboardText)

        let urlAction = CustomClipboardAction(
            template: "{{content|trim|urlencode}}"
        )
        #expect(urlAction.renderedOutput(for: item) == "Hello%20world")
    }

    @Test
    func imageTemplatesUseLocalMetadataAndRespectScope() {
        let image = ClipboardItem(
            content: "",
            kind: .image,
            imageFileName: "cached.png",
            imageSourceURL: "https://example.com/image.png",
            imageOriginalPath: "/tmp/image.png",
            ocrText: "hello"
        )
        let action = CustomClipboardAction(
            title: "Image reference",
            template: "{{imageURL}}{{newline}}{{imagePath}}{{newline}}{{ocr|uppercase}}",
            scope: .image
        )

        #expect(
            action.renderedOutput(for: image)
                == "https://example.com/image.png\n/tmp/image.png\nHELLO"
        )
        #expect(
            action.renderedOutput(
                for: ClipboardItem(content: "text", kind: .text)
            ) == nil
        )
    }

    @Test
    func invalidTemplatesAndUnavailableExternalContentAreNotGenerated() {
        let item = ClipboardItem(content: "hello", kind: .text)
        let malformed = CustomClipboardAction(template: "{{unknown}}")
        let disabled = CustomClipboardAction(isEnabled: false)
        let external = ClipboardItem(
            content: "preview",
            kind: .text,
            contentFileName: "large.txt"
        )

        #expect(malformed.renderedOutput(for: item) == nil)
        #expect(disabled.renderedOutput(for: item) == nil)
        #expect(CustomClipboardAction().renderedOutput(for: external) == nil)
        #expect(
            ClipboardActionFactory.actions(
                for: item,
                customActions: [malformed, disabled]
            ).allSatisfy { !$0.id.hasPrefix("custom-") }
        )
    }

    @Test
    func settingsPersistAndResetCustomActions() throws {
        let suiteName = "PastePilotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let action = CustomClipboardAction(
            title: "Trim",
            template: "{{content|trim}}",
            scope: .all
        )
        let settings = AppSettings(defaults: defaults)
        settings.customClipboardActions = [action]

        let restored = AppSettings(defaults: defaults)
        #expect(restored.customClipboardActions == [action])

        restored.reset()
        #expect(restored.customClipboardActions.isEmpty)
        #expect(AppSettings(defaults: defaults).customClipboardActions.isEmpty)
    }
}
