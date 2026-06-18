import Foundation
import Testing

@Suite
struct LocalizationTests {
    @Test
    func simplifiedChineseStringsCoverLocalizedSourceKeys() throws {
        let root = packageRootURL()
        let sourceKeys = try localizedKeys(
            under: root.appendingPathComponent("Sources/PastePilot")
        )
        let translatedKeys = try stringsFileKeys(
            at: root.appendingPathComponent(
                "Sources/PastePilot/Resources/zh-Hans.lproj/Localizable.strings"
            )
        )
        let missingKeys = sourceKeys.subtracting(translatedKeys).sorted()
        let unexpectedKeys = translatedKeys.subtracting(sourceKeys).sorted()

        if !missingKeys.isEmpty {
            Issue.record(
                "Missing zh-Hans translations: \(missingKeys.joined(separator: ", "))"
            )
        }
        if !unexpectedKeys.isEmpty {
            Issue.record(
                "Unused zh-Hans translations: \(unexpectedKeys.joined(separator: ", "))"
            )
        }
    }

    private func packageRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func localizedKeys(under sourceURL: URL) throws -> Set<String> {
        let fileManager = FileManager.default
        let enumerator = try #require(
            fileManager.enumerator(
                at: sourceURL,
                includingPropertiesForKeys: nil
            )
        )
        let regex = try NSRegularExpression(
            pattern: #""((?:\\.|[^"\\])*)"\.localized\b"#
        )
        var keys = Set<String>()

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(content.startIndex..., in: content)
            for match in regex.matches(in: content, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: content) else {
                    continue
                }
                keys.insert(unescapedStringLiteralContent(String(content[keyRange])))
            }
        }

        return keys
    }

    private func stringsFileKeys(at fileURL: URL) throws -> Set<String> {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let regex = try NSRegularExpression(
            pattern: #"(?m)^\s*"((?:\\.|[^"\\])*)"\s*="#
        )
        let range = NSRange(content.startIndex..., in: content)
        return Set(
            regex.matches(in: content, range: range).compactMap { match in
                guard let keyRange = Range(match.range(at: 1), in: content) else {
                    return nil
                }
                return unescapedStringLiteralContent(String(content[keyRange]))
            }
        )
    }

    private func unescapedStringLiteralContent(_ rawValue: String) -> String {
        let jsonString = "\"\(rawValue)\""
        return (try? JSONDecoder().decode(
            String.self,
            from: Data(jsonString.utf8)
        )) ?? rawValue
    }
}
