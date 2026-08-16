import Foundation

struct LocalActionPluginCatalogState {
    let directoryURL: URL
    private(set) var plugins: [LocalActionPlugin] = []
    private(set) var errors: [String] = []
    private(set) var disabledIdentifiers: Set<String>

    init(directoryURL: URL, disabledIdentifiers: Set<String>) {
        self.directoryURL = directoryURL
        self.disabledIdentifiers = disabledIdentifiers
    }

    mutating func reload() {
        let catalog = LocalActionPluginLoader.load(from: directoryURL)
        plugins = catalog.plugins
        errors = catalog.errors
    }

    mutating func setPlugin(_ identifier: String, isEnabled: Bool) {
        if isEnabled {
            disabledIdentifiers.remove(identifier)
        } else {
            disabledIdentifiers.insert(identifier)
        }
    }

    mutating func removeAllDisabledIdentifiers() {
        disabledIdentifiers.removeAll()
    }

    func createDirectory() throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    mutating func importPlugins(from sourceURLs: [URL]) throws {
        try LocalActionPluginFileOperations.importPlugins(
            from: sourceURLs,
            into: directoryURL
        )
        reload()
    }

    func exportPlugin(
        _ plugin: LocalActionPlugin,
        to destinationURL: URL
    ) throws {
        try LocalActionPluginFileOperations.exportPlugin(
            plugin,
            from: directoryURL,
            to: destinationURL
        )
    }
}
