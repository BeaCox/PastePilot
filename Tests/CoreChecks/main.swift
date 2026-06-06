import Foundation

private var failures: [String] = []

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures.append(message)
    }
}

check(ContentAnalyzer.analyze(#"{"name":"PastePilot"}"#).kind == .json, "recognizes JSON")
check(ContentAnalyzer.analyze("git status --short").kind == .command, "recognizes commands")
check(
    ContentAnalyzer.analyze("TypeError: undefined\n at index.js:10").kind == .error,
    "recognizes errors"
)

let secret = "API_KEY=super-secret-value"
check(ContentAnalyzer.analyze(secret).containsSensitiveData, "detects sensitive content")
check(!ContentAnalyzer.redacted(secret).contains("super-secret-value"), "redacts sensitive content")

let json = #"{"b":2,"a":1}"#
check(ContentTransformer.formatJSON(json)?.contains("\n") == true, "formats JSON")
check(ContentTransformer.minifyJSON(json) == #"{"a":1,"b":2}"#, "minifies JSON")

let typeScript = ContentTransformer.jsonToTypeScript(#"{"name":"Pilot","active":true}"#)
check(typeScript?.contains("interface Root") == true, "creates TypeScript interface")
check(typeScript?.contains("active: boolean;") == true, "infers booleans")

check(ContentTransformer.toCamelCase("user_profile-id") == "userProfileId", "creates camelCase")
check(ContentTransformer.toSnakeCase("userProfileID") == "user_profile_id", "creates snake_case")
check(
    ContentTransformer.escapeString("hello\n\"world\"") == #"hello\n\"world\""#,
    "escapes strings"
)

let terminalTranscript = """
$ git status --short
 M Sources/App.swift
❯ npm test
Tests passed
"""
check(
    ContentTransformer.extractShellCommands(terminalTranscript)
        == "git status --short\nnpm test",
    "extracts prompted shell commands"
)
check(
    ContentTransformer.shellCodeBlock("$ git status")
        == "```sh\ngit status\n```",
    "creates shell code blocks"
)

let multilineCommand = """
$ curl https://example.com \\
>   -H "Accept: application/json"
"""
check(
    ContentTransformer.extractShellCommands(multilineCommand)
        == "curl https://example.com \\\n  -H \"Accept: application/json\"",
    "preserves multiline shell commands"
)
check(
    ContentTransformer.extractShellCommands("The price is $100") == nil,
    "ignores currency as a shell prompt"
)
check(
    ContentTransformer.imageMarkdown(
        reference: "https://example.com/image one.png",
        altText: "demo"
    ) == "![demo](<https://example.com/image one.png>)",
    "creates image Markdown"
)

let commandItem = ClipboardItem(content: terminalTranscript, kind: .command)
let commandActions = ClipboardActionFactory.compactActions(for: commandItem)
let commandOutputs = commandActions.compactMap(\.preview)
check(
    commandOutputs.count == Set(commandOutputs).count,
    "deduplicates command actions with identical output"
)
check(
    commandActions.map(\.id) == ["extract-shell", "extracted-shell-code-block", "quote-command"],
    "orders transcript command actions"
)

let legacyItemJSON = """
{
  "id": "F1D906A4-C840-4D49-A8C8-137AA0CD0BF6",
  "content": "legacy",
  "kind": "text",
  "createdAt": "2026-06-06T14:02:05Z",
  "isPinned": false,
  "containsSensitiveData": false
}
"""
let legacyDecoder = JSONDecoder()
legacyDecoder.dateDecodingStrategy = .iso8601
let legacyItem = try? legacyDecoder.decode(
    ClipboardItem.self,
    from: Data(legacyItemJSON.utf8)
)
check(legacyItem?.sourceAppName == nil, "decodes history without source metadata")

let imageItem = ClipboardItem(
    content: "图片 320 × 180",
    kind: .image,
    imageFileName: "test.png",
    imageWidth: 320,
    imageHeight: 180,
    imageByteCount: 1_024,
    imageDigest: "digest",
    imageSourceURL: "https://example.com/image.png"
)
let imageEncoder = JSONEncoder()
imageEncoder.dateEncodingStrategy = .iso8601
let encodedImageItem = try? imageEncoder.encode(imageItem)
let decodedImageItem = encodedImageItem.flatMap {
    try? legacyDecoder.decode(ClipboardItem.self, from: $0)
}
check(
    decodedImageItem?.isImage == true
        && decodedImageItem?.imageWidth == 320
        && decodedImageItem?.imageSourceURL == "https://example.com/image.png",
    "persists image metadata"
)
check(
    ClipboardActionFactory.compactActions(for: imageItem).map(\.id)
        == ["copy-image-markdown", "copy-image-url", "copy-image-cache-path"],
    "offers web image Markdown, URL, and path actions"
)

let localImageItem = ClipboardItem(
    content: "图片 100 × 100",
    kind: .image,
    imageFileName: "local.png",
    imageOriginalPath: "/Users/demo/Pictures/local.png"
)
check(
    ClipboardActionFactory.compactActions(for: localImageItem).map(\.id)
        == ["copy-image-markdown", "copy-image-path"],
    "offers local image Markdown and file path actions"
)

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
check(
    ClipboardHistoryOrdering.pinnedFirst(
        [newRecent, oldPinned]
    ).map(\.content) == ["pinned", "recent"],
    "places pinned items above recent history"
)
check(
    HotKeyFormatter.display(keyCode: 49, modifiers: 2_048) == "⌥Space",
    "formats the default global hot key"
)

let settingsSuiteName = "PastePilotCoreChecks.\(UUID().uuidString)"
let settingsDefaults = UserDefaults(suiteName: settingsSuiteName)!
settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
let testSettings = AppSettings(defaults: settingsDefaults)
check(
    testSettings.monitoringEnabled
        && testSettings.historyLimit == 100
        && testSettings.imageSizeLimitMB == 25
        && testSettings.hotKeyCode == 49
        && testSettings.hotKeyModifiers == 2_048,
    "uses expected settings defaults"
)
testSettings.historyLimit = 200
testSettings.imageSizeLimitMB = 50
testSettings.hotKeyCode = 8
testSettings.hotKeyModifiers = 256
testSettings.ignoredBundleIdentifiers = """
com.apple.keychainaccess

 com.example.private
"""
let restoredSettings = AppSettings(defaults: settingsDefaults)
check(
    restoredSettings.historyLimit == 200
        && restoredSettings.imageSizeLimitMB == 50
        && restoredSettings.hotKeyCode == 8
        && restoredSettings.hotKeyModifiers == 256,
    "persists preferences"
)
check(
    restoredSettings.ignoredBundleIdentifierSet
        == ["com.apple.keychainaccess", "com.example.private"],
    "parses ignored application bundle identifiers"
)
restoredSettings.reset()
check(
    restoredSettings.historyLimit == 100
        && restoredSettings.ignoredBundleIdentifiers.isEmpty
        && restoredSettings.hotKeyCode == 49
        && restoredSettings.hotKeyModifiers == 2_048,
    "restores default preferences"
)
settingsDefaults.removePersistentDomain(forName: settingsSuiteName)

if failures.isEmpty {
    print("All \(29) core checks passed.")
} else {
    failures.forEach { print("FAIL: \($0)") }
    exit(1)
}
