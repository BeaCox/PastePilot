import Foundation

enum LocalActionPluginFileOperations {
    enum OperationError: LocalizedError, Equatable {
        case tooManyPlugins(Int)
        case fileNameAlreadyExists(String)
        case identifierAlreadyExists(String)
        case duplicateImportFileName(String)
        case duplicateImportIdentifier(String)
        case installedPluginChanged(String)

        var errorDescription: String? {
            switch self {
            case let .tooManyPlugins(limit):
                "No more than %d plugin files can be installed.".localized(limit)
            case let .fileNameAlreadyExists(fileName):
                "A plugin file named '%@' is already installed.".localized(fileName)
            case let .identifierAlreadyExists(identifier):
                "A plugin with identifier '%@' is already installed.".localized(identifier)
            case let .duplicateImportFileName(fileName):
                "More than one selected plugin is named '%@'.".localized(fileName)
            case let .duplicateImportIdentifier(identifier):
                "More than one selected plugin uses identifier '%@'.".localized(identifier)
            case let .installedPluginChanged(fileName):
                "The installed plugin file '%@' no longer matches the loaded plugin.".localized(
                    fileName
                )
            }
        }
    }

    @discardableResult
    static func importPlugins(
        from sourceURLs: [URL],
        into directoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> [LocalActionPlugin] {
        guard !sourceURLs.isEmpty else { return [] }

        let existingEntries = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let existingPluginFiles = existingEntries.filter {
            $0.pathExtension.lowercased() == "json"
        }
        guard existingPluginFiles.count + sourceURLs.count
                <= LocalActionPluginLoader.maximumPluginCount else {
            throw OperationError.tooManyPlugins(
                LocalActionPluginLoader.maximumPluginCount
            )
        }

        let existingCatalog = LocalActionPluginLoader.load(
            from: directoryURL,
            fileManager: fileManager
        )
        let existingFileNames = Set(
            existingEntries.map { $0.lastPathComponent.lowercased() }
        )
        let existingIdentifiers = Set(existingCatalog.plugins.map(\.id))
        var importFileNames: Set<String> = []
        var importIdentifiers: Set<String> = []
        var validated: [(sourceURL: URL, plugin: LocalActionPlugin)] = []

        for sourceURL in sourceURLs {
            let plugin = try LocalActionPluginLoader.loadPlugin(at: sourceURL)
            let normalizedFileName = sourceURL.lastPathComponent.lowercased()
            guard !existingFileNames.contains(normalizedFileName) else {
                throw OperationError.fileNameAlreadyExists(sourceURL.lastPathComponent)
            }
            guard !existingIdentifiers.contains(plugin.id) else {
                throw OperationError.identifierAlreadyExists(plugin.id)
            }
            guard importFileNames.insert(normalizedFileName).inserted else {
                throw OperationError.duplicateImportFileName(sourceURL.lastPathComponent)
            }
            guard importIdentifiers.insert(plugin.id).inserted else {
                throw OperationError.duplicateImportIdentifier(plugin.id)
            }
            validated.append((sourceURL, plugin))
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        var copiedURLs: [URL] = []
        do {
            for candidate in validated {
                let destinationURL = directoryURL.appendingPathComponent(
                    candidate.sourceURL.lastPathComponent,
                    isDirectory: false
                )
                try fileManager.copyItem(at: candidate.sourceURL, to: destinationURL)
                copiedURLs.append(destinationURL)
            }
        } catch {
            for copiedURL in copiedURLs {
                try? fileManager.removeItem(at: copiedURL)
            }
            throw error
        }
        return validated.map(\.plugin)
    }

    static func exportPlugin(
        _ plugin: LocalActionPlugin,
        from directoryURL: URL,
        to destinationURL: URL
    ) throws {
        let sourceURL = directoryURL.appendingPathComponent(
            plugin.fileName,
            isDirectory: false
        )
        let installedPlugin = try LocalActionPluginLoader.loadPlugin(at: sourceURL)
        guard installedPlugin.id == plugin.id else {
            throw OperationError.installedPluginChanged(plugin.fileName)
        }
        let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        try data.write(to: destinationURL, options: [.atomic])
    }
}
