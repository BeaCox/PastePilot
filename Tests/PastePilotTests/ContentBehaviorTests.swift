import AppKit
import Foundation
import Testing
@testable import PastePilot

@Suite
struct ContentBehaviorTests {
    @Test
    func contentAnalysis() {
        #expect(ContentAnalyzer.analyze(#"{"name":"PastePilot"}"#).kind == .json)
        #expect(ContentAnalyzer.analyze("git status --short").kind == .command)
        #expect(ContentAnalyzer.analyze("$ npm install").kind == .command)
        #expect(ContentAnalyzer.analyze("npx create-react-app my-app").kind == .command)
        #expect(ContentAnalyzer.analyze("sudo apt install nginx").kind == .command)
        #expect(ContentAnalyzer.analyze("terraform init").kind == .command)
        #expect(ContentAnalyzer.analyze("aws s3 ls").kind == .command)
        #expect(
            ContentAnalyzer.analyze("TypeError: undefined\n at index.js:10").kind
                == .error
        )
    }

    @Test
    func sensitiveContentDetectionAndRedaction() {
        let secret = "API_KEY=super-secret-value"
        #expect(ContentAnalyzer.analyze(secret).containsSensitiveData)
        #expect(!ContentAnalyzer.redacted(secret).contains("super-secret-value"))
    }

    @Test
    func jsonTransforms() {
        let json = #"{"b":2,"a":1}"#
        #expect(ContentTransformer.formatJSON(json)?.contains("\n") == true)
        #expect(ContentTransformer.minifyJSON(json) == #"{"a":1,"b":2}"#)

        let typeScript = ContentTransformer.jsonToTypeScript(
            #"{"name":"Pilot","active":true}"#
        )
        #expect(typeScript?.contains("interface Root") == true)
        #expect(typeScript?.contains("active: boolean;") == true)
    }

    @Test
    func textTransforms() {
        #expect(ContentTransformer.toCamelCase("user_profile-id") == "userProfileId")
        #expect(ContentTransformer.toSnakeCase("userProfileID") == "user_profile_id")
        #expect(
            ContentTransformer.escapeString("hello\n\"world\"")
                == #"hello\n\"world\""#
        )
        #expect(
            ContentTransformer.imageMarkdown(
                reference: "https://example.com/image one.png",
                altText: "demo"
            ) == "![demo](<https://example.com/image one.png>)"
        )
    }

    @Test
    func shellCommandExtraction() {
        let transcript = """
        $ git status --short
         M Sources/App.swift
        ❯ npm test
        Tests passed
        """
        #expect(
            ContentTransformer.extractShellCommands(transcript)
                == "git status --short\nnpm test"
        )
        #expect(
            ContentTransformer.shellCodeBlock("$ git status")
                == "```sh\ngit status\n```"
        )

        let multiline = """
        $ curl https://example.com \\
        >   -H "Accept: application/json"
        """
        #expect(
            ContentTransformer.extractShellCommands(multiline)
                == "curl https://example.com \\\n  -H \"Accept: application/json\""
        )
        #expect(ContentTransformer.extractShellCommands("The price is $100") == nil)
        #expect(
            ContentTransformer.extractShellCommands(
                "$ git clone https://github.com/user/repo.git\n$ cd repo\n$ npm install"
            ) == "git clone https://github.com/user/repo.git\ncd repo\nnpm install"
        )
        #expect(ContentTransformer.extractShellCommands("$ npm install") == "npm install")
    }

    @Test
    func commandActionsAreOrderedAndDeduplicated() {
        let item = ClipboardItem(
            content: "$ git status\n M Sources/App.swift\n❯ npm test\nTests passed",
            kind: .command
        )
        let actions = ClipboardActionFactory.compactActions(for: item)
        let outputs = actions.compactMap(\.preview)
        #expect(outputs.count == Set(outputs).count)
        #expect(
            actions.map(\.id)
                == ["extract-shell", "extracted-shell-code-block", "quote-command"]
        )
    }

    @Test
    func inlinePreviewClosingActionsAreIdentified() {
        #expect(
            ClipboardAction(
                id: "quick-look",
                title: "Quick Look",
                detail: "",
                symbol: "eye",
                effect: .quickLook([URL(fileURLWithPath: "/tmp/file.txt")])
            )
            .closesInlinePreview
        )
        #expect(
            ClipboardAction(
                id: "reveal-files",
                title: "Show in Finder",
                detail: "",
                symbol: "folder",
                effect: .revealFiles([URL(fileURLWithPath: "/tmp/file.txt")])
            )
            .closesInlinePreview == false
        )
        #expect(
            ClipboardAction(
                id: "copy",
                title: "Copy",
                detail: "",
                symbol: "doc.on.doc",
                effect: .copy("text")
            )
            .closesInlinePreview == false
        )
    }

    @Test
    func imageFileAndRichTextActions() {
        let webImage = ClipboardItem(
            content: "Image 320 × 180",
            kind: .image,
            imageFileName: "test.png",
            imageWidth: 320,
            imageHeight: 180,
            imageByteCount: 1_024,
            imageDigest: "digest",
            imageSourceURL: "https://example.com/image.png"
        )
        #expect(
            ClipboardActionFactory.actions(for: webImage).map(\.id)
                == ["copy-image", "copy-image-url", "copy-image-markdown", "quick-look", "reveal-files"]
        )
        #expect(
            ClipboardActionFactory.compactActions(for: webImage).map(\.id)
                == ["copy-image-url", "copy-image-markdown", "quick-look"]
        )

        let localImage = ClipboardItem(
            content: "Image 100 × 100",
            kind: .image,
            imageFileName: "local.png",
            imageOriginalPath: "/Users/demo/Pictures/local.png"
        )
        #expect(
            ClipboardActionFactory.actions(for: localImage).map(\.id)
                == ["copy-image", "copy-image-file", "copy-image-markdown", "quick-look", "reveal-files"]
        )
        #expect(
            ClipboardActionFactory.compactActions(for: localImage).map(\.id)
                == ["copy-image-file", "copy-image-markdown", "quick-look"]
        )

        let cachedImage = ClipboardItem(
            content: "Image 80 × 80",
            kind: .image,
            imageFileName: "cached.png"
        )
        #expect(
            ClipboardActionFactory.actions(for: cachedImage).map(\.id)
                == ["copy-image", "copy-image-file", "copy-image-markdown", "quick-look", "reveal-files"]
        )

        let file = ClipboardItem(
            content: "one.txt\ntwo.pdf",
            kind: .file,
            filePaths: ["/tmp/one.txt", "/tmp/two.pdf"]
        )
        #expect(file.fileURLs.count == 2)
        #expect(
            ClipboardActionFactory.actions(for: file).map(\.id)
                == ["copy-files", "quick-look", "reveal-files"]
        )
        #expect(ClipboardActionFactory.copyAction(for: file).id == "copy-files")

        let richText = ClipboardItem(
            content: "Formatted text",
            kind: .richText,
            richTextRTFBase64: Data("{\\rtf1 Formatted text}".utf8).base64EncodedString(),
            richTextHTML: "<b>Formatted text</b>"
        )
        #expect(richText.hasRichText)
        #expect(
            ClipboardActionFactory.actions(for: richText).map(\.id).contains("copy-html")
        )
    }

    @Test
    func clipboardItemCompatibilityAndOrdering() throws {
        let legacyJSON = """
        {
          "id": "F1D906A4-C840-4D49-A8C8-137AA0CD0BF6",
          "content": "legacy",
          "kind": "text",
          "createdAt": "2026-06-06T14:02:05Z",
          "isPinned": false,
          "containsSensitiveData": false
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacyItem = try decoder.decode(
            ClipboardItem.self,
            from: Data(legacyJSON.utf8)
        )
        #expect(legacyItem.sourceAppName == nil)

        let oldPinned = ClipboardItem(
            content: "pinned",
            kind: .text,
            createdAt: Date(timeIntervalSince1970: 1),
            isPinned: true
        )
        let newRecent = ClipboardItem(
            content: "recent",
            kind: .text,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        #expect(
            ClipboardHistoryOrdering.pinnedFirst([newRecent, oldPinned]).map(\.content)
                == ["pinned", "recent"]
        )
    }

    @Test
    func hotKeyFormatting() {
        #expect(
            HotKeyFormatter.display(keyCode: 49, modifiers: 2_048) == "⌥Space"
        )
    }

    @Test
    func pastePilotMenuBarIconUsesStandardCanvas() throws {
        let image = try #require(
            AppIconRenderer.menuBarImage(style: .pastepilot, filled: true)
        )
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(MenuBarIconStyle.pastepilot.previewImage.size == image.size)
    }
}
