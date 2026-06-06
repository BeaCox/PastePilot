import AppKit
import Foundation

struct ClipboardAction: Identifiable {
    enum Effect {
        case copy(String)
        case copyImage(String)
        case copyImageMarkdown(
            fileName: String,
            sourceURL: String?,
            originalPath: String?
        )
        case copyCachedImagePath(String)
        case open(URL)
    }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    let effect: Effect

    var preview: String? {
        if case let .copy(content) = effect { return content }
        return nil
    }
}

enum ClipboardActionFactory {
    static func actions(for item: ClipboardItem) -> [ClipboardAction] {
        if item.kind == .image, let fileName = item.imageFileName {
            var imageActions = [
                ClipboardAction(
                    id: "copy-image",
                    title: "复制图片",
                    detail: "将原始图片重新写入剪贴板",
                    symbol: "doc.on.doc",
                    effect: .copyImage(fileName)
                ),
                ClipboardAction(
                    id: "copy-image-markdown",
                    title: "复制 Markdown",
                    detail: "优先使用网页 URL，其次使用本地图片路径",
                    symbol: "text.badge.checkmark",
                    effect: .copyImageMarkdown(
                        fileName: fileName,
                        sourceURL: item.imageSourceURL,
                        originalPath: item.imageOriginalPath
                    )
                )
            ]
            if let sourceURL = item.imageSourceURL {
                imageActions.append(
                    ClipboardAction(
                        id: "copy-image-url",
                        title: "复制图片 URL",
                        detail: "复制网页图片的原始地址",
                        symbol: "link",
                        effect: .copy(sourceURL)
                    )
                )
            }
            if let originalPath = item.imageOriginalPath {
                imageActions.append(
                    ClipboardAction(
                        id: "copy-image-path",
                        title: "复制文件路径",
                        detail: "复制图片原文件的本地路径",
                        symbol: "folder",
                        effect: .copy(originalPath)
                    )
                )
            } else {
                imageActions.append(
                    ClipboardAction(
                        id: "copy-image-cache-path",
                        title: "复制缓存路径",
                        detail: "复制 PastePilot 保存的 PNG 路径",
                        symbol: "internaldrive",
                        effect: .copyCachedImagePath(fileName)
                    )
                )
            }
            return deduplicated(imageActions)
        }

        var actions = [
            ClipboardAction(
                id: "copy",
                title: "复制原文",
                detail: "不做修改，重新写入剪贴板",
                symbol: "doc.on.doc",
                effect: .copy(item.content)
            )
        ]

        switch item.kind {
        case .image:
            break
        case .json:
            if let formatted = ContentTransformer.formatJSON(item.content) {
                actions.append(
                    ClipboardAction(
                        id: "format-json",
                        title: "格式化 JSON",
                        detail: "排序键名并添加缩进，便于阅读",
                        symbol: "increase.indent",
                        effect: .copy(formatted)
                    )
                )
            }
            if let minified = ContentTransformer.minifyJSON(item.content) {
                actions.append(
                    ClipboardAction(
                        id: "minify-json",
                        title: "压缩 JSON",
                        detail: "移除空白，适合请求参数和配置",
                        symbol: "decrease.indent",
                        effect: .copy(minified)
                    )
                )
            }
            if let typeScript = ContentTransformer.jsonToTypeScript(item.content) {
                actions.append(
                    ClipboardAction(
                        id: "typescript",
                        title: "生成 TypeScript 类型",
                        detail: "根据字段值推断 interface",
                        symbol: "t.square",
                        effect: .copy(typeScript)
                    )
                )
            }
        case .url:
            if let url = URL(string: item.content) {
                actions.insert(
                    ClipboardAction(
                        id: "open-url",
                        title: "在浏览器中打开",
                        detail: url.host ?? "打开这个链接",
                        symbol: "safari",
                        effect: .open(url)
                    ),
                    at: 0
                )
            }
        case .color:
            actions.append(
                ClipboardAction(
                    id: "uppercase-color",
                    title: "复制大写色值",
                    detail: "统一十六进制颜色格式",
                    symbol: "paintpalette",
                    effect: .copy(item.content.uppercased())
                )
            )
        case .command:
            actions.append(contentsOf: shellActions(for: item.content))
            actions.append(
                ClipboardAction(
                    id: "quote-command",
                    title: "转成可嵌入字符串",
                    detail: "转义引号、反斜杠和换行",
                    symbol: "quote.opening",
                    effect: .copy(ContentTransformer.escapeString(item.content))
                )
            )
        case .error:
            if let extracted = ContentTransformer.extractShellCommands(item.content) {
                actions.append(contentsOf: extractedCommandActions(extracted))
            }
            actions.append(
                ClipboardAction(
                    id: "markdown-error",
                    title: "包成 Markdown 代码块",
                    detail: "方便粘贴到 Issue 或聊天中",
                    symbol: "text.badge.checkmark",
                    effect: .copy("```\n\(item.content)\n```")
                )
            )
        case .markdown, .code, .text:
            if let extracted = ContentTransformer.extractShellCommands(item.content) {
                actions.append(contentsOf: extractedCommandActions(extracted))
            }
            actions.append(contentsOf: textActions(for: item.content))
        }

        return deduplicated(actions)
    }

    static func compactActions(for item: ClipboardItem) -> [ClipboardAction] {
        Array(actions(for: item).filter {
            $0.id != "copy" && $0.id != "copy-image"
        }.prefix(3))
    }

    static func copyAction(for item: ClipboardItem) -> ClipboardAction {
        if let fileName = item.imageFileName {
            return ClipboardAction(
                id: "copy-image",
                title: "复制图片",
                detail: "将原始图片重新写入剪贴板",
                symbol: "doc.on.doc",
                effect: .copyImage(fileName)
            )
        }
        return ClipboardAction(
            id: "copy",
            title: "复制原文",
            detail: "不做修改，重新写入剪贴板",
            symbol: "doc.on.doc",
            effect: .copy(item.content)
        )
    }

    @MainActor
    static func perform(_ action: ClipboardAction, using store: ClipboardStore) -> String {
        switch action.effect {
        case let .copy(content):
            store.copy(content)
            return "已复制：\(action.title)"
        case let .copyImage(fileName):
            return store.copyImage(fileName: fileName)
                ? "已复制图片"
                : "图片文件已丢失"
        case let .copyImageMarkdown(fileName, sourceURL, originalPath):
            let reference = sourceURL
                ?? originalPath
                ?? store.imagePath(fileName: fileName)
            let altText = originalPath
                .map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
                ?? "image"
            store.copy(
                ContentTransformer.imageMarkdown(
                    reference: reference,
                    altText: altText
                )
            )
            return "已复制图片 Markdown"
        case let .copyCachedImagePath(fileName):
            store.copy(store.imagePath(fileName: fileName))
            return "已复制缓存路径"
        case let .open(url):
            NSWorkspace.shared.open(url)
            return "已打开链接"
        }
    }

    private static func textActions(for content: String) -> [ClipboardAction] {
        [
            ClipboardAction(
                id: "camel-case",
                title: "转换为 camelCase",
                detail: "适合 JavaScript、Swift 变量名",
                symbol: "textformat",
                effect: .copy(ContentTransformer.toCamelCase(content))
            ),
            ClipboardAction(
                id: "snake-case",
                title: "转换为 snake_case",
                detail: "适合数据库字段和 Python 变量",
                symbol: "textformat.abc",
                effect: .copy(ContentTransformer.toSnakeCase(content))
            ),
            ClipboardAction(
                id: "escape",
                title: "转义为字符串",
                detail: "处理引号、反斜杠和换行",
                symbol: "quote.opening",
                effect: .copy(ContentTransformer.escapeString(content))
            )
        ]
    }

    private static func shellActions(for content: String) -> [ClipboardAction] {
        if let extracted = ContentTransformer.extractShellCommands(content),
           extracted.trimmingCharacters(in: .whitespacesAndNewlines)
            != content.trimmingCharacters(in: .whitespacesAndNewlines) {
            return extractedCommandActions(extracted)
        }
        return [
            ClipboardAction(
                id: "shell-code-block",
                title: "包成 Shell 代码块",
                detail: "生成带 sh 语言标记的 Markdown 代码块",
                symbol: "chevron.left.forwardslash.chevron.right",
                effect: .copy(ContentTransformer.shellCodeBlock(content))
            )
        ]
    }

    private static func extractedCommandActions(_ extracted: String) -> [ClipboardAction] {
        [
            ClipboardAction(
                id: "extract-shell",
                title: "提取命令",
                detail: "移除提示符和终端输出，只保留可复制的命令",
                symbol: "terminal",
                effect: .copy(extracted)
            ),
            ClipboardAction(
                id: "extracted-shell-code-block",
                title: "命令代码块",
                detail: "将提取出的命令包成 Markdown Shell 代码块",
                symbol: "chevron.left.forwardslash.chevron.right",
                effect: .copy(ContentTransformer.shellCodeBlock(extracted))
            )
        ]
    }

    private static func deduplicated(_ actions: [ClipboardAction]) -> [ClipboardAction] {
        var seenEffects: Set<String> = []
        return actions.filter { action in
            let key: String
            switch action.effect {
            case let .copy(content):
                key = "copy:\(content)"
            case let .copyImage(fileName):
                key = "image:\(fileName)"
            case let .copyImageMarkdown(fileName, sourceURL, originalPath):
                key = "markdown:\(sourceURL ?? originalPath ?? fileName)"
            case let .copyCachedImagePath(fileName):
                key = "cache-path:\(fileName)"
            case let .open(url):
                key = "open:\(url.absoluteString)"
            }
            return seenEffects.insert(key).inserted
        }
    }
}

extension ContentKind {
    var localizedTitle: String {
        switch self {
        case .image: "图片"
        case .json: "JSON 数据"
        case .url: "网页链接"
        case .color: "颜色值"
        case .command: "终端命令"
        case .error: "错误信息"
        case .markdown: "Markdown 文本"
        case .code: "代码片段"
        case .text: "纯文本"
        }
    }

    var explanation: String {
        switch self {
        case .image: "识别到图片，可以预览并重新复制。"
        case .json: "已解析结构，可以格式化、压缩或生成类型。"
        case .url: "这是一个可访问的链接，可以直接打开或复制。"
        case .color: "识别到颜色值，可以统一格式后使用。"
        case .command: "识别到终端命令，不会自动执行。"
        case .error: "识别到报错内容，可以整理后发到 Issue 或聊天。"
        case .markdown: "识别到 Markdown，可以继续处理命名或字符串格式。"
        case .code: "识别到代码片段，可以复制或转义后嵌入字符串。"
        case .text: "可以转换变量命名风格或转义为字符串。"
        }
    }
}
