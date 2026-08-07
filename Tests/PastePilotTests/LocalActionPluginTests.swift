import Foundation
import Testing
@testable import PastePilot

@Suite
struct LocalActionPluginTests {
    @Test
    func bundledExampleAndManifestSchemaAreAvailable() throws {
        let exampleURL = try #require(LocalActionPluginResources.examplePluginURL)
        let schemaURL = try #require(LocalActionPluginResources.manifestSchemaURL)
        #expect(FileManager.default.fileExists(atPath: exampleURL.path))
        #expect(FileManager.default.fileExists(atPath: schemaURL.path))

        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.copyItem(
            at: exampleURL,
            to: directory.appendingPathComponent(exampleURL.lastPathComponent)
        )

        let catalog = LocalActionPluginLoader.load(from: directory)
        #expect(catalog.errors.isEmpty)
        #expect(catalog.plugins.map(\.id) == ["dev.pastepilot.example.issue-tools"])

        let schemaObject = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL))
                as? [String: Any]
        )
        #expect(schemaObject["$schema"] as? String == "https://json-schema.org/draft/2020-12/schema")
        #expect(schemaObject["title"] as? String == "PastePilot Local Action Plugin Manifest v1")
    }

    @Test
    func pluginContentTypeGeneratesStableMatchedAction() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePlugin(
            """
            {
              "schemaVersion": 1,
              "identifier": "dev.pastepilot.issue-tools",
              "name": "Issue Tools",
              "version": "1.0.0",
              "contentTypes": [
                {
                  "id": "issue-key",
                  "title": "Issue Key",
                  "matcher": {
                    "type": "regularExpression",
                    "pattern": "^[A-Z]+-[0-9]+$"
                  }
                }
              ],
              "actions": [
                {
                  "id": "copy-issue-url",
                  "title": "Copy Issue URL",
                  "detail": "Build a local issue link",
                  "template": "https://issues.example/browse/{{content|urlencode}}",
                  "contentTypes": ["issue-key"]
                }
              ]
            }
            """,
            named: "issue-tools.json",
            in: directory
        )

        let catalog = LocalActionPluginLoader.load(from: directory)
        #expect(catalog.errors.isEmpty)
        let plugin = try #require(catalog.plugins.first)
        #expect(plugin.id == "dev.pastepilot.issue-tools")
        #expect(plugin.contentTypeNames == ["Issue Key"])

        let matchingItem = ClipboardItem(content: "APP-42", kind: .text)
        let generated = try #require(
            ClipboardActionFactory.actions(
                for: matchingItem,
                customActions: catalog.actions
            ).first { $0.id == "plugin-dev.pastepilot.issue-tools-copy-issue-url" }
        )
        #expect(generated.preview == "https://issues.example/browse/APP-42")
        #expect(generated.detail == "Build a local issue link")

        let otherItem = ClipboardItem(content: "not an issue", kind: .text)
        #expect(
            ClipboardActionFactory.actions(
                for: otherItem,
                customActions: catalog.actions
            ).allSatisfy { !$0.id.hasPrefix("plugin-") }
        )
    }

    @Test
    func settingsReloadsPluginsWithoutPersistingThemAsUserActions() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "PastePilotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let settings = AppSettings(
            defaults: defaults,
            pluginsDirectoryURL: directory
        )
        #expect(settings.localActionPlugins.isEmpty)

        try writePlugin(validLiteralPlugin, named: "commit.json", in: directory)
        settings.reloadLocalActionPlugins()

        #expect(settings.localActionPlugins.map(\.name) == ["Commit Tools"])
        #expect(settings.customClipboardActions.isEmpty)
        #expect(settings.availableCustomClipboardActions.count == 1)
    }

    @Test
    func pluginEnablementPersistsAndControlsAvailableActions() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePlugin(validLiteralPlugin, named: "commit.json", in: directory)

        let defaultsName = "PastePilotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let identifier = "dev.pastepilot.commit-tools"
        let settings = AppSettings(
            defaults: defaults,
            pluginsDirectoryURL: directory
        )
        #expect(settings.isLocalActionPluginEnabled(identifier))
        #expect(settings.availableCustomClipboardActions.count == 1)

        settings.setLocalActionPlugin(identifier, isEnabled: false)
        #expect(!settings.isLocalActionPluginEnabled(identifier))
        #expect(settings.availableCustomClipboardActions.isEmpty)

        let restored = AppSettings(
            defaults: defaults,
            pluginsDirectoryURL: directory
        )
        #expect(!restored.isLocalActionPluginEnabled(identifier))
        #expect(restored.localActionPlugins.count == 1)
        #expect(restored.availableCustomClipboardActions.isEmpty)

        restored.setLocalActionPlugin(identifier, isEnabled: true)
        #expect(restored.availableCustomClipboardActions.count == 1)
    }

    @Test
    func settingsImportsAndExportsIndividualPlugins() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        let pluginsDirectory = root.appendingPathComponent("Plugins", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        try writePlugin(validLiteralPlugin, named: "commit.json", in: sourceDirectory)
        let sourceURL = sourceDirectory.appendingPathComponent("commit.json")

        let defaultsName = "PastePilotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let settings = AppSettings(
            defaults: defaults,
            pluginsDirectoryURL: pluginsDirectory
        )

        try settings.importLocalActionPlugins(from: [sourceURL])
        #expect(settings.localActionPlugins.map(\.id) == ["dev.pastepilot.commit-tools"])
        #expect(
            FileManager.default.fileExists(
                atPath: pluginsDirectory.appendingPathComponent("commit.json").path
            )
        )

        let exportURL = root.appendingPathComponent("Exported.json")
        let plugin = try #require(settings.localActionPlugins.first)
        try settings.exportLocalActionPlugin(plugin, to: exportURL)
        #expect(try Data(contentsOf: exportURL) == Data(contentsOf: sourceURL))

        #expect(
            throws: LocalActionPluginFileOperations.OperationError
                .fileNameAlreadyExists("commit.json")
        ) {
            try settings.importLocalActionPlugins(from: [sourceURL])
        }
        #expect(settings.localActionPlugins.count == 1)
    }

    @Test
    func invalidAndDuplicatePluginManifestsAreRejected() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePlugin(validLiteralPlugin, named: "a.json", in: directory)
        try writePlugin(validLiteralPlugin, named: "b.json", in: directory)
        try writePlugin(
            validLiteralPlugin.replacingOccurrences(
                of: #""type": "literal", "pattern": "fix:""#,
                with: #""type": "regularExpression", "pattern": "[""#
            ),
            named: "invalid-regex.json",
            in: directory
        )

        let catalog = LocalActionPluginLoader.load(from: directory)
        #expect(catalog.plugins.count == 1)
        #expect(catalog.errors.count == 2)
        #expect(catalog.errors.contains { $0.contains("identifier") })
        #expect(catalog.errors.contains { $0.contains("contentTypes[0].matcher.pattern") })
    }

    @Test
    func validationErrorsNameMissingAndReferencedFields() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePlugin(
            validLiteralPlugin.replacingOccurrences(
                of: #""contentTypes": ["conventional-commit"]"#,
                with: #""contentTypes": ["missing-type"]"#
            ),
            named: "unknown-type.json",
            in: directory
        )
        try writePlugin(
            validLiteralPlugin.replacingOccurrences(
                of: #""template": "{{content|uppercase}}","#,
                with: ""
            ),
            named: "missing-template.json",
            in: directory
        )

        let catalog = LocalActionPluginLoader.load(from: directory)
        #expect(catalog.plugins.isEmpty)
        #expect(catalog.errors.contains {
            $0.contains("actions[0].contentTypes[0]") && $0.contains("missing-type")
        })
        #expect(catalog.errors.contains { $0.contains("actions[0].template") })
    }

    @Test
    func matchersAreBoundedAndHonorCaseSensitivity() {
        let insensitive = LocalPluginContentMatcher(type: .literal, pattern: "FIX:")
        let sensitive = LocalPluginContentMatcher(
            type: .literal,
            pattern: "FIX:",
            caseSensitive: true
        )
        #expect(insensitive.matches("fix: bug"))
        #expect(!sensitive.matches("fix: bug"))
        #expect(
            !insensitive.matches(
                String(repeating: "x", count: LocalPluginContentMatcher.maximumMatchedContentLength + 1)
            )
        )
    }

    private var validLiteralPlugin: String {
        """
        {
          "schemaVersion": 1,
          "identifier": "dev.pastepilot.commit-tools",
          "name": "Commit Tools",
          "version": "1",
          "contentTypes": [
            {
              "id": "conventional-commit",
              "title": "Conventional Commit",
              "matcher": { "type": "literal", "pattern": "fix:" }
            }
          ],
          "actions": [
            {
              "id": "uppercase",
              "title": "Uppercase Commit",
              "template": "{{content|uppercase}}",
              "contentTypes": ["conventional-commit"]
            }
          ]
        }
        """
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PastePilotPluginTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func writePlugin(
        _ contents: String,
        named name: String,
        in directory: URL
    ) throws {
        try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
    }
}
