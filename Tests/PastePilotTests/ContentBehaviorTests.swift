import AppKit
import Foundation
import Testing
@testable import PastePilot

@Suite
struct ContentBehaviorTests {
    @Test
    func contentAnalysis() {
        #expect(ContentAnalyzer.analyze(#"{"name":"PastePilot"}"#).kind == .json)
        #expect(ContentAnalyzer.analyze("https://example.com/path?q=1").kind == .url)
        #expect(ContentAnalyzer.analyze("mailto:support@example.com").kind == .url)
        #expect(ContentAnalyzer.analyze("error: missing value").kind == .error)
        #expect(ContentAnalyzer.analyze("custom-scheme:value").kind == .text)
        #expect(ContentAnalyzer.analyze("git status --short").kind == .command)
        #expect(ContentAnalyzer.analyze("$ npm install").kind == .command)
        #expect(ContentAnalyzer.analyze("npx create-react-app my-app").kind == .command)
        #expect(ContentAnalyzer.analyze("sudo apt install nginx").kind == .command)
        #expect(ContentAnalyzer.analyze("terraform init").kind == .command)
        #expect(ContentAnalyzer.analyze("aws s3 ls").kind == .command)
        #expect(ContentAnalyzer.analyze("gh pr checkout 42").kind == .command)
        #expect(ContentAnalyzer.analyze("jq '.items[]' response.json").kind == .command)
        #expect(ContentAnalyzer.analyze("poetry install").kind == .command)
        #expect(ContentAnalyzer.analyze("psql postgres://localhost/app").kind == .command)
        #expect(
            ContentAnalyzer.analyze("NODE_ENV=production npm run build").kind
                == .command
        )
        #expect(
            ContentAnalyzer.analyze(#"APP_ENV="local dev" npm test"#).kind
                == .command
        )
        #expect(
            ContentAnalyzer.analyze(#"sudo -E APP_ENV="local dev" npm test"#).kind
                == .command
        )
        #expect(
            ContentAnalyzer.analyze(#"env APP_ENV='local dev' ./gradlew test"#).kind
                == .command
        )
        #expect(ContentAnalyzer.analyze("./gradlew test").kind == .command)
        #expect(ContentAnalyzer.analyze("NODE_ENV=production").kind == .text)
        #expect(ContentAnalyzer.analyze(#"APP_ENV="local dev""#).kind == .text)
        #expect(
            ContentAnalyzer.analyze("TypeError: undefined\n at index.js:10").kind
                == .error
        )
        #expect(
            ContentAnalyzer.analyze(
                "function greet(name) {\n  return `Hello ${name}`;\n}"
            ).kind == .code
        )
    }

    @Test
    func sensitiveContentDetectionAndRedaction() {
        let secret = "API_KEY=super-secret-value"
        #expect(ContentAnalyzer.analyze(secret).containsSensitiveData)
        #expect(ContentAnalyzer.redacted(secret) == "API_KEY=••••••••")

        let quotedPassword = #"password="hunter two""#
        #expect(ContentAnalyzer.containsSensitiveData(quotedPassword))
        #expect(ContentAnalyzer.redacted(quotedPassword) == #"password="••••••••""#)

        let singleQuotedSecret = "client_secret='value with spaces'"
        #expect(ContentAnalyzer.containsSensitiveData(singleQuotedSecret))
        #expect(
            ContentAnalyzer.redacted(singleQuotedSecret)
                == "client_secret='••••••••'"
        )

        let authorizationHeader = "Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345"
        #expect(ContentAnalyzer.containsSensitiveData(authorizationHeader))
        #expect(ContentAnalyzer.redacted(authorizationHeader) == "Authorization: Bearer ••••••••")

        let lowercaseBearer = "authorization: bearer abcdefghijklmnopqrstuvwxyz012345"
        #expect(ContentAnalyzer.containsSensitiveData(lowercaseBearer))
        #expect(ContentAnalyzer.redacted(lowercaseBearer) == "authorization: bearer ••••••••")

        let openAIKey = "sk-1234567890abcdefghijklmnop"
        #expect(ContentAnalyzer.containsSensitiveData(openAIKey))
        #expect(ContentAnalyzer.redacted(openAIKey) == "••••••••")

        let githubToken = "ghp_1234567890abcdefghijklmnop"
        #expect(ContentAnalyzer.containsSensitiveData(githubToken))
        #expect(ContentAnalyzer.redacted(githubToken) == "••••••••")

        let githubRefreshToken = "ghr_1234567890abcdefghijklmnop"
        #expect(ContentAnalyzer.containsSensitiveData(githubRefreshToken))
        #expect(ContentAnalyzer.redacted(githubRefreshToken) == "••••••••")

        let fineGrainedGitHubToken = "github_pat_1234567890_abcdefghijklmnopQRST"
        #expect(ContentAnalyzer.containsSensitiveData(fineGrainedGitHubToken))
        #expect(ContentAnalyzer.redacted(fineGrainedGitHubToken) == "••••••••")

        let slackToken = [
            "xoxb",
            "123456789012",
            "123456789012",
            "abcdefghijklmnop"
        ].joined(separator: "-")
        #expect(ContentAnalyzer.containsSensitiveData(slackToken))
        #expect(ContentAnalyzer.redacted(slackToken) == "••••••••")

        let awsAccessKey = "AKIA1234567890ABCDEF"
        #expect(ContentAnalyzer.containsSensitiveData(awsAccessKey))
        #expect(ContentAnalyzer.redacted(awsAccessKey) == "••••••••")

        let awsSecret = "aws_secret_access_key=abcdefghijklmnopqrstuvwxyz1234567890ABCD"
        #expect(ContentAnalyzer.containsSensitiveData(awsSecret))
        #expect(ContentAnalyzer.redacted(awsSecret) == "aws_secret_access_key=••••••••")

        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.signature"
        #expect(ContentAnalyzer.containsSensitiveData(jwt))
        #expect(ContentAnalyzer.redacted(jwt) == "••••••••")

        let privateKey = """
        -----BEGIN PRIVATE KEY-----
        abcdefg
        -----END PRIVATE KEY-----
        """
        #expect(ContentAnalyzer.containsSensitiveData(privateKey))
        #expect(ContentAnalyzer.redacted(privateKey) == "••••••••")
        #expect(ContentAnalyzer.containsSensitiveData("-----BEGIN OPENSSH PRIVATE KEY-----"))
    }

    @Test
    func userSensitivePatternsDetectAndRedactCustomContent() {
        let patterns = UserSensitivePattern.patterns(from: """
        project raven
        regex:customer-[0-9]+
        regex:[
        """)

        #expect(patterns.count == 3)
        #expect(
            ContentAnalyzer.containsSensitiveData(
                "Project Raven launch notes",
                userPatterns: patterns
            )
        )
        #expect(
            ContentAnalyzer.redacted(
                "Project Raven launch notes",
                userPatterns: patterns
            ) == "•••••••• launch notes"
        )
        #expect(
            ContentAnalyzer.containsSensitiveData(
                "customer-42 profile",
                userPatterns: patterns
            )
        )
        #expect(
            ContentAnalyzer.redacted(
                "customer-42 profile",
                userPatterns: patterns
            ) == "•••••••• profile"
        )
        #expect(
            !ContentAnalyzer.containsSensitiveData(
                "ordinary note",
                userPatterns: patterns
            )
        )
    }

    @Test
    func textPreviewKeepsLargeContentBounded() {
        let content = String(repeating: "a", count: TextPreview.countScanCharacterLimit + 1)
        let item = ClipboardItem(content: content, kind: .text)
        let snippet = TextPreview.detailSnippet(for: item, revealsSensitiveContent: false)

        #expect(snippet.text.count == TextPreview.initialDetailCharacterLimit)
        #expect(snippet.isTruncated)
        #expect(
            TextPreview.characterCountDescription(for: content)
                .hasPrefix("\(TextPreview.countScanCharacterLimit)+")
        )
    }

    @Test
    func textPreviewLoadsMoreInBoundedChunks() {
        let content = String(
            repeating: "a",
            count: TextPreview.maxInteractiveDetailCharacterLimit + 1
        )
        let item = ClipboardItem(content: content, kind: .text)
        let nextLimit = TextPreview.nextDetailCharacterLimit(
            after: TextPreview.initialDetailCharacterLimit
        )
        let snippet = TextPreview.detailSnippet(
            for: item,
            revealsSensitiveContent: false,
            maxCharacters: nextLimit
        )

        #expect(nextLimit == TextPreview.initialDetailCharacterLimit + TextPreview.detailLoadStep)
        #expect(snippet.text.count == nextLimit)
        #expect(snippet.isTruncated)
        #expect(
            TextPreview.nextDetailCharacterLimit(
                after: TextPreview.maxInteractiveDetailCharacterLimit
            ) == TextPreview.maxInteractiveDetailCharacterLimit
        )
    }

    @Test
    func rowSummaryUsesOnlyAPrefix() {
        let content = "first line\n" + String(repeating: "secret", count: 1_000)
        let item = ClipboardItem(content: content, kind: .text)

        #expect(TextPreview.summary(for: item).count <= TextPreview.summaryCharacterLimit)
        #expect(!TextPreview.summary(for: item).contains("\n"))
    }

    @Test
    func searchQueryMatchesAllTermsCaseInsensitively() {
        let query = ClipboardSearchQuery("  alpha BETA  ")

        #expect(query.rawValue == "alpha BETA")
        #expect(query.terms == ["alpha", "BETA"])
        #expect(query.searchText == "alpha BETA")
        #expect(query.canUseTrigramFullTextSearch)
        #expect(query.matches("beta value before alpha value"))
        #expect(!query.matches("alpha only"))
        #expect(!ClipboardSearchQuery("go ui").canUseTrigramFullTextSearch)
    }

    @Test
    func searchQueryParsesQuotedPhrasesAndFilters() {
        let item = ClipboardItem(
            content: "alpha beta deploy",
            kind: .json,
            isPinned: true,
            sourceAppName: "Terminal",
            sourceBundleIdentifier: "com.apple.Terminal",
            ocrText: "invoice paid"
        )
        let query = ClipboardSearchQuery(#"kind:json app:"terminal" pinned:true has:ocr "alpha beta""#)

        #expect(query.terms == ["alpha beta"])
        #expect(query.searchText == "alpha beta")
        #expect(query.canUseTrigramFullTextSearch)
        #expect(query.matches("prefix alpha beta suffix"))
        #expect(!query.matches("alpha then beta"))
        #expect(query.matchesFilters(item))
        #expect(!ClipboardSearchQuery("kind:image").matchesFilters(item))
        #expect(!ClipboardSearchQuery("app:safari").matchesFilters(item))
        #expect(!ClipboardSearchQuery("pinned:false").matchesFilters(item))
        #expect(!ClipboardSearchQuery("has:file").matchesFilters(item))
        #expect(ClipboardSearchQuery("kind:json").isEmpty == false)
        #expect(ClipboardSearchQuery("kind:json").hasSearchTerms == false)
    }

    @Test
    func jsonTransforms() {
        let json = #"{"b":2,"a":1}"#
        #expect(ContentTransformer.formatJSON(json)?.contains("\n") == true)
        #expect(ContentTransformer.minifyJSON(json) == #"{"a":1,"b":2}"#)

        let typeScript = ContentTransformer.jsonToTypeScript(
            #"{"name":"Pilot","active":true,"count":1}"#
        )
        #expect(typeScript?.contains("interface Root") == true)
        #expect(typeScript?.contains("active: boolean;") == true)
        #expect(typeScript?.contains("count: number;") == true)

        let arrayTypeScript = ContentTransformer.jsonToTypeScript(
            #"{"users":[{"id":1,"name":"Ada"},{"active":true,"id":2,"name":null}]}"#
        )
        #expect(arrayTypeScript?.contains("users: {") == true)
        #expect(arrayTypeScript?.contains("active?: boolean;") == true)
        #expect(arrayTypeScript?.contains("id: number;") == true)
        #expect(arrayTypeScript?.contains("name: string | null;") == true)
        #expect(arrayTypeScript?.contains("}[];") == true)

        #expect(
            ContentTransformer.jsonToTypeScript(#"[1,"two",null]"#)
                == "type Root = (number | string | null)[];"
        )

        let escapedKeyTypeScript = ContentTransformer.jsonToTypeScript(
            #"{"line\nbreak":1,"path\\name":true,"quote\"key":"x"}"#
        )
        #expect(escapedKeyTypeScript?.contains(#""line\nbreak": number;"#) == true)
        #expect(escapedKeyTypeScript?.contains(#""path\\name": boolean;"#) == true)
        #expect(escapedKeyTypeScript?.contains(#""quote\"key": string;"#) == true)
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
        #expect(
            ContentTransformer.markdownCodeBlock("let value = 1")
                == "```\nlet value = 1\n```"
        )
        #expect(
            ContentTransformer.markdownCodeBlock("```swift\nlet value = 1\n```")
                == "````\n```swift\nlet value = 1\n```\n````"
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
        #expect(
            ContentTransformer.extractShellCommands(
                #"""
                NODE_ENV=production npm run build
                APP_ENV="local dev" npm test
                sudo -E CI=1 ./gradlew test
                env APP_ENV='local dev' npm test
                """#
            ) == #"""
                NODE_ENV=production npm run build
                APP_ENV="local dev" npm test
                sudo -E CI=1 ./gradlew test
                env APP_ENV='local dev' npm test
                """#
        )
        #expect(ContentTransformer.extractShellCommands("NODE_ENV=production") == nil)
        #expect(
            ContentTransformer.extractShellCommands(#"APP_ENV="local dev""#) == nil
        )

        let consoleFence = """
        ```console
        $ npm install
        added 1 package
        $ npm test
        Tests passed
        ```
        """
        #expect(
            ContentTransformer.extractShellCommands(consoleFence)
                == "npm install\nnpm test"
        )

        let bashFenceWithTitle = """
        ```bash title="setup"
        gh pr checkout 42
        jq '.items[]' response.json
        ```
        """
        #expect(
            ContentTransformer.extractShellCommands(bashFenceWithTitle)
                == "gh pr checkout 42\njq '.items[]' response.json"
        )
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
    func codeActionsPreferMarkdownCodeBlockOverStringTransforms() {
        let item = ClipboardItem(
            content: "function greet(name) {\n  return `Hello ${name}`;\n}",
            kind: .code
        )
        let actions = ClipboardActionFactory.actions(for: item)
        let actionIDs = actions.map(\.id)

        #expect(actionIDs == ["copy", "markdown-code-block"])
        #expect(!actionIDs.contains("camel-case"))
        #expect(!actionIDs.contains("snake-case"))
        #expect(!actionIDs.contains("escape"))
        #expect(
            ClipboardActionFactory.compactActions(for: item).map(\.id)
                == ["markdown-code-block"]
        )
        #expect(
            actions.compactMap(\.preview).contains(
                "```\nfunction greet(name) {\n  return `Hello ${name}`;\n}\n```"
            )
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

        let imageWithOCRText = ClipboardItem(
            content: "Image 640 × 480",
            kind: .image,
            imageFileName: "ocr.png",
            ocrText: "recognized text"
        )
        #expect(
            ClipboardActionFactory.actions(for: imageWithOCRText).map(\.id)
                == ["copy-image", "copy-ocr-text", "copy-image-file", "copy-image-markdown", "quick-look", "reveal-files"]
        )
        #expect(
            ClipboardActionFactory.compactActions(for: imageWithOCRText).map(\.id)
                == ["copy-ocr-text", "copy-image-file", "copy-image-markdown"]
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
    func imageActionsSkipUnavailableOriginalFileOperations() {
        let actions = ClipboardActionFactory.imageActions(
            fileName: "cached.png",
            sourceURL: nil,
            originalPath: nil,
            fileURL: nil,
            usesCachedFile: false
        )

        #expect(actions.map(\.id) == ["copy-image", "copy-image-markdown"])
        for action in actions {
            switch action.effect {
            case .copyFiles(let urls), .quickLook(let urls), .revealFiles(let urls):
                #expect(!urls.isEmpty)
            default:
                break
            }
        }
    }

    @Test
    @MainActor
    func hotKeyRegistrationWarningsDescribeAllFailures() {
        #expect(AppDelegate.hotKeyRegistrationWarning(for: []) == nil)
        #expect(
            AppDelegate.hotKeyRegistrationWarning(for: [.openPanel])
                == "Open PastePilot shortcut is already in use.".localized
        )
        #expect(
            AppDelegate.hotKeyRegistrationWarning(for: [.pastePlainText])
                == "Paste as Plain Text shortcut is already in use.".localized
        )
        #expect(
            AppDelegate.hotKeyRegistrationWarning(for: [.openPanel, .pastePlainText])
                == "Open PastePilot and Paste as Plain Text shortcuts are already in use.".localized
        )
    }

    @Test
    @MainActor
    func plainTextPasteFailureNoticesDescribeRecoverableFailures() {
        #expect(AppDelegate.plainTextPasteFailureNotice(for: .pasted) == nil)
        #expect(
            AppDelegate.plainTextPasteFailureNotice(for: .accessibilityRequired) == nil
        )
        #expect(
            AppDelegate.plainTextPasteFailureNotice(for: .noText)
                == PastePilotNotice(
                    "No text is available to paste as plain text.".localized,
                    style: .warning
                )
        )
        #expect(
            AppDelegate.plainTextPasteFailureNotice(for: .pasteboardWriteFailed)
                == PastePilotNotice(
                    "Plain text could not be prepared for pasting.".localized,
                    style: .error
                )
        )
        #expect(
            AppDelegate.plainTextPasteFailureNotice(for: .busy)
                == PastePilotNotice(
                    "Plain-text paste is already in progress.".localized,
                    style: .warning
                )
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
            HotKeyFormatter.display(
                keyCode: AppSettings.defaultOpenHotKeyCode,
                modifiers: AppSettings.defaultOpenHotKeyModifiers
            ) == "⌥Space"
        )
    }

    @Test
    @MainActor
    func pastePilotMenuBarIconUsesStandardCanvas() throws {
        let image = try #require(
            AppIconRenderer.menuBarImage(style: .pastepilot, filled: true)
        )
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(MenuBarIconStyle.pastepilot.previewImage.size == NSSize(width: 15, height: 15))
        for style in MenuBarIconStyle.allCases {
            #expect(style.previewImage.size.width > 0)
            #expect(style.previewImage.size.height > 0)
        }
    }
}
