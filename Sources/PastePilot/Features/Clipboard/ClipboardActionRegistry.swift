import Foundation

struct ClipboardActionDefinition: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let acceptedKinds: Set<ContentKind>
    let inputSource: ClipboardAction.InputSource
    let outputEffect: ClipboardAction.OutputEffect
    let closeBehavior: ClipboardAction.CloseBehavior

    func action(
        effect: ClipboardAction.Effect,
        id: String? = nil,
        title: String? = nil,
        detail: String? = nil,
        symbol: String? = nil,
        acceptedKinds: Set<ContentKind>? = nil,
        inputSource: ClipboardAction.InputSource? = nil,
        outputEffect: ClipboardAction.OutputEffect? = nil,
        closeBehavior: ClipboardAction.CloseBehavior? = nil
    ) -> ClipboardAction {
        ClipboardAction(
            id: id ?? self.id,
            title: title ?? self.title,
            detail: detail ?? self.detail,
            symbol: symbol ?? self.symbol,
            acceptedKinds: acceptedKinds ?? self.acceptedKinds,
            inputSource: inputSource ?? self.inputSource,
            outputEffect: outputEffect ?? self.outputEffect,
            closeBehavior: closeBehavior ?? self.closeBehavior,
            effect: effect
        )
    }
}

enum ClipboardActionRegistry {
    private static let allKinds = Set(ContentKind.allCases)
    private static let textKinds: Set<ContentKind> = [.markdown, .text]
    private static let shellExtractionKinds: Set<ContentKind> = [
        .command,
        .error,
        .markdown,
        .text
    ]
    private static let fileReferenceKinds: Set<ContentKind> = [.file, .image]

    static let copyText = ClipboardActionDefinition(
        id: "copy",
        title: "Copy Original".localized,
        detail: "Copy as-is back to the clipboard".localized,
        symbol: "doc.on.doc",
        acceptedKinds: allKinds,
        inputSource: .itemContent,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let copyOriginalRepresentation = ClipboardActionDefinition(
        id: "copy-original",
        title: "Copy Original".localized,
        detail: "Copy as-is back to the clipboard".localized,
        symbol: "doc.on.doc",
        acceptedKinds: allKinds,
        inputSource: .itemIdentity,
        outputEffect: .clipboardItem,
        closeBehavior: .keepInlinePreview
    )

    static let copyFiles = ClipboardActionDefinition(
        id: "copy-files",
        title: "Copy Files".localized,
        detail: "Write the original files back to the clipboard".localized,
        symbol: "doc.on.doc",
        acceptedKinds: fileReferenceKinds,
        inputSource: .fileURLs,
        outputEffect: .clipboardFiles,
        closeBehavior: .keepInlinePreview
    )

    static let copyRichText = ClipboardActionDefinition(
        id: "copy-rich-text",
        title: "Copy with Formatting".localized,
        detail: "Preserve fonts, styles, colors, and links".localized,
        symbol: "textformat",
        acceptedKinds: [.richText],
        inputSource: .richText,
        outputEffect: .clipboardRichText,
        closeBehavior: .keepInlinePreview
    )

    static let copyHTML = ClipboardActionDefinition(
        id: "copy-html",
        title: "Copy HTML Source".localized,
        detail: "Copy the underlying HTML markup".localized,
        symbol: "chevron.left.forwardslash.chevron.right",
        acceptedKinds: [.richText],
        inputSource: .richText,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let copyImage = ClipboardActionDefinition(
        id: "copy-image",
        title: "Copy Image".localized,
        detail: "Write the original image back to the clipboard".localized,
        symbol: "photo",
        acceptedKinds: [.image],
        inputSource: .imageAsset,
        outputEffect: .clipboardImage,
        closeBehavior: .keepInlinePreview
    )

    static let copyImageURL = ClipboardActionDefinition(
        id: "copy-image-url",
        title: "Copy Image URL".localized,
        detail: "Copy the original web image address".localized,
        symbol: "link",
        acceptedKinds: [.image],
        inputSource: .imageURL,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let copyImageFile = ClipboardActionDefinition(
        id: "copy-image-file",
        title: "Copy File".localized,
        detail: "Write the cached PNG file back to the clipboard".localized,
        symbol: "doc.on.doc",
        acceptedKinds: [.image],
        inputSource: .imageFile,
        outputEffect: .clipboardFiles,
        closeBehavior: .keepInlinePreview
    )

    static let copyImageMarkdown = ClipboardActionDefinition(
        id: "copy-image-markdown",
        title: "Copy Markdown".localized,
        detail: "Prefers web URL, falls back to local file path".localized,
        symbol: "text.badge.checkmark",
        acceptedKinds: [.image],
        inputSource: .imageAsset,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let copyOCRText = ClipboardActionDefinition(
        id: "copy-ocr-text",
        title: "Copy OCR Text".localized,
        detail: "Copy recognized text from this image".localized,
        symbol: "text.viewfinder",
        acceptedKinds: [.image],
        inputSource: .ocrText,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let quickLook = ClipboardActionDefinition(
        id: "quick-look",
        title: "Quick Look".localized,
        detail: "Preview using the macOS system viewer".localized,
        symbol: "eye",
        acceptedKinds: fileReferenceKinds,
        inputSource: .fileURLs,
        outputEffect: .quickLook,
        closeBehavior: .closeInlinePreview
    )

    static let revealFiles = ClipboardActionDefinition(
        id: "reveal-files",
        title: "Show in Finder".localized,
        detail: "Reveal the original file location".localized,
        symbol: "folder",
        acceptedKinds: fileReferenceKinds,
        inputSource: .fileURLs,
        outputEffect: .revealInFinder,
        closeBehavior: .keepInlinePreview
    )

    static let formatJSON = ClipboardActionDefinition(
        id: "format-json",
        title: "Format JSON".localized,
        detail: "Sort keys and indent for readability".localized,
        symbol: "increase.indent",
        acceptedKinds: [.json],
        inputSource: .generatedContent,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let minifyJSON = ClipboardActionDefinition(
        id: "minify-json",
        title: "Minify JSON".localized,
        detail: "Remove whitespace for payloads and configs".localized,
        symbol: "decrease.indent",
        acceptedKinds: [.json],
        inputSource: .generatedContent,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let typeScript = ClipboardActionDefinition(
        id: "typescript",
        title: "Generate TypeScript Types".localized,
        detail: "Infer an interface from field values".localized,
        symbol: "t.square",
        acceptedKinds: [.json],
        inputSource: .generatedContent,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let openURL = ClipboardActionDefinition(
        id: "open-url",
        title: "Open in Browser".localized,
        detail: "Open this link".localized,
        symbol: "safari",
        acceptedKinds: [.url],
        inputSource: .url,
        outputEffect: .openURL,
        closeBehavior: .keepInlinePreview
    )

    static let uppercaseColor = ClipboardActionDefinition(
        id: "uppercase-color",
        title: "Copy Uppercased Color".localized,
        detail: "Normalize hex color format".localized,
        symbol: "paintpalette",
        acceptedKinds: [.color],
        inputSource: .generatedContent,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let quoteCommand = ClipboardActionDefinition(
        id: "quote-command",
        title: "Escape for String Embedding".localized,
        detail: "Escape quotes, backslashes, and newlines".localized,
        symbol: "quote.opening",
        acceptedKinds: [.command],
        inputSource: .generatedContent,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let markdownError = ClipboardActionDefinition(
        id: "markdown-error",
        title: "Wrap in Markdown Code Block".localized,
        detail: "Ready to paste into issues or chats".localized,
        symbol: "text.badge.checkmark",
        acceptedKinds: [.error],
        inputSource: .generatedContent,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let markdownCodeBlock = ClipboardActionDefinition(
        id: "markdown-code-block",
        title: "Wrap in Markdown Code Block".localized,
        detail: "Ready to paste into issues or chats".localized,
        symbol: "text.badge.checkmark",
        acceptedKinds: [.code],
        inputSource: .generatedContent,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let camelCase = ClipboardActionDefinition(
        id: "camel-case",
        title: "Convert to camelCase".localized,
        detail: "For JavaScript and Swift variable names".localized,
        symbol: "arrow.up.forward",
        acceptedKinds: textKinds,
        inputSource: .generatedContent,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let snakeCase = ClipboardActionDefinition(
        id: "snake-case",
        title: "Convert to snake_case".localized,
        detail: "For database fields and Python variables".localized,
        symbol: "arrow.down.forward",
        acceptedKinds: textKinds,
        inputSource: .generatedContent,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let escapeString = ClipboardActionDefinition(
        id: "escape",
        title: "Escape as String".localized,
        detail: "Handle quotes, backslashes, and newlines".localized,
        symbol: "quote.opening",
        acceptedKinds: textKinds,
        inputSource: .generatedContent,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let shellCodeBlock = ClipboardActionDefinition(
        id: "shell-code-block",
        title: "Wrap in Shell Code Block".localized,
        detail: "Generate a Markdown code block with sh language tag".localized,
        symbol: "chevron.left.forwardslash.chevron.right",
        acceptedKinds: [.command],
        inputSource: .generatedContent,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let extractShell = ClipboardActionDefinition(
        id: "extract-shell",
        title: "Extract Commands".localized,
        detail: "Strip prompts and output, keep only runnable commands".localized,
        symbol: "terminal",
        acceptedKinds: shellExtractionKinds,
        inputSource: .generatedContent,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let extractedShellCodeBlock = ClipboardActionDefinition(
        id: "extracted-shell-code-block",
        title: "Command Code Block".localized,
        detail: "Wrap extracted commands in a Markdown shell code block".localized,
        symbol: "chevron.left.forwardslash.chevron.right",
        acceptedKinds: shellExtractionKinds,
        inputSource: .generatedContent,
        outputEffect: .clipboardText,
        closeBehavior: .keepInlinePreview
    )

    static let allDefinitions: [ClipboardActionDefinition] = [
        copyText,
        copyOriginalRepresentation,
        copyFiles,
        copyRichText,
        copyHTML,
        copyImage,
        copyImageURL,
        copyImageFile,
        copyImageMarkdown,
        copyOCRText,
        quickLook,
        revealFiles,
        formatJSON,
        minifyJSON,
        typeScript,
        openURL,
        uppercaseColor,
        quoteCommand,
        markdownError,
        markdownCodeBlock,
        camelCase,
        snakeCase,
        escapeString,
        shellCodeBlock,
        extractShell,
        extractedShellCodeBlock
    ]

    static func definition(for id: String) -> ClipboardActionDefinition? {
        allDefinitions.first { $0.id == id }
    }
}
