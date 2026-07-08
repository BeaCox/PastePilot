import Foundation

struct HistoryBackupResult: Equatable {
    let archiveURL: URL
}

struct HistoryRestoreResult: Equatable {
    let preRestoreBackupURL: URL
}

enum HistoryBackupError: LocalizedError {
    case missingDatabase
    case missingManifest
    case invalidManifest
    case unsupportedSchemaVersion(Int)
    case invalidArchiveLayout(String)
    case archiveCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingDatabase:
            "History database is missing."
        case .missingManifest:
            "Backup manifest is missing."
        case .invalidManifest:
            "Backup manifest is invalid."
        case .unsupportedSchemaVersion(let version):
            "Backup schema version \(version) is not supported."
        case .invalidArchiveLayout(let reason):
            "Backup archive layout is invalid: \(reason)"
        case .archiveCommandFailed(let message):
            "Backup archive command failed: \(message)"
        }
    }
}

struct HistoryBackupService {
    private struct BackupManifest: Codable {
        static let archiveKind = "PastePilotBackup"
        static let currentSchemaVersion = 1

        let kind: String
        let schemaVersion: Int
        let createdAt: Date

        init(createdAt: Date = Date()) {
            self.kind = Self.archiveKind
            self.schemaVersion = Self.currentSchemaVersion
            self.createdAt = createdAt
        }
    }

    private enum Path {
        static let manifest = "manifest.json"
        static let database = "history.sqlite"
        static let images = "images"
        static let text = "text"
        static let sqliteWAL = "history.sqlite-wal"
        static let sqliteSHM = "history.sqlite-shm"
    }

    let dataDirectoryURL: URL
    private let fileManager: FileManager

    init(
        dataDirectoryURL: URL,
        fileManager: FileManager = .default
    ) {
        self.dataDirectoryURL = dataDirectoryURL
        self.fileManager = fileManager
    }

    func exportBackup(to archiveURL: URL) throws -> HistoryBackupResult {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let backupRoot = temporaryDirectory.appendingPathComponent(
            "PastePilotBackup",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: backupRoot,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: backupRoot.appendingPathComponent(Path.images, isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: backupRoot.appendingPathComponent(Path.text, isDirectory: true),
            withIntermediateDirectories: true
        )

        try writeManifest(to: backupRoot)
        try copyDatabase(to: backupRoot)
        try copyDirectoryContents(
            from: dataDirectoryURL.appendingPathComponent(
                Path.images,
                isDirectory: true
            ),
            to: backupRoot.appendingPathComponent(Path.images, isDirectory: true)
        )
        try copyDirectoryContents(
            from: dataDirectoryURL.appendingPathComponent(
                Path.text,
                isDirectory: true
            ),
            to: backupRoot.appendingPathComponent(Path.text, isDirectory: true)
        )

        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }
        try runDitto(arguments: [
            "-c",
            "-k",
            "--norsrc",
            backupRoot.path,
            archiveURL.path
        ])
        return HistoryBackupResult(archiveURL: archiveURL)
    }

    func restoreBackup(
        from archiveURL: URL,
        preRestoreBackupDirectoryURL: URL? = nil
    ) throws -> HistoryRestoreResult {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let extractionURL = temporaryDirectory.appendingPathComponent(
            "ExtractedBackup",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: extractionURL,
            withIntermediateDirectories: true
        )
        try runDitto(arguments: ["-x", "-k", archiveURL.path, extractionURL.path])

        let backupRoot = try validatedBackupRoot(in: extractionURL)
        let preRestoreBackupURL = try makePreRestoreBackupURL(
            in: preRestoreBackupDirectoryURL
        )
        _ = try exportBackup(to: preRestoreBackupURL)
        try replaceLocalData(with: backupRoot)

        return HistoryRestoreResult(preRestoreBackupURL: preRestoreBackupURL)
    }

    private func writeManifest(to backupRoot: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(BackupManifest())
        try data.write(
            to: backupRoot.appendingPathComponent(Path.manifest),
            options: .atomic
        )
    }

    private func copyDatabase(to backupRoot: URL) throws {
        let source = dataDirectoryURL.appendingPathComponent(Path.database)
        guard fileManager.fileExists(atPath: source.path) else {
            throw HistoryBackupError.missingDatabase
        }
        try fileManager.copyItem(
            at: source,
            to: backupRoot.appendingPathComponent(Path.database)
        )
    }

    private func copyDirectoryContents(from source: URL, to destination: URL) throws {
        guard fileManager.fileExists(atPath: source.path) else { return }
        let children = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        )
        for child in children {
            try fileManager.copyItem(
                at: child,
                to: destination.appendingPathComponent(child.lastPathComponent)
            )
        }
    }

    private func replaceLocalData(with backupRoot: URL) throws {
        try fileManager.createDirectory(
            at: dataDirectoryURL,
            withIntermediateDirectories: true
        )
        let removablePaths = [
            Path.database,
            Path.sqliteWAL,
            Path.sqliteSHM,
            Path.images,
            Path.text
        ]
        for path in removablePaths {
            let url = dataDirectoryURL.appendingPathComponent(path)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }

        try fileManager.copyItem(
            at: backupRoot.appendingPathComponent(Path.database),
            to: dataDirectoryURL.appendingPathComponent(Path.database)
        )
        try fileManager.copyItem(
            at: backupRoot.appendingPathComponent(Path.images, isDirectory: true),
            to: dataDirectoryURL.appendingPathComponent(Path.images, isDirectory: true)
        )
        try fileManager.copyItem(
            at: backupRoot.appendingPathComponent(Path.text, isDirectory: true),
            to: dataDirectoryURL.appendingPathComponent(Path.text, isDirectory: true)
        )
    }

    private func makePreRestoreBackupURL(
        in directoryURL: URL?
    ) throws -> URL {
        let directory = directoryURL ?? dataDirectoryURL
            .deletingLastPathComponent()
            .appendingPathComponent("PastePilot Pre-Restore Backups", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let baseName = "PastePilot-PreRestore-\(timestampForFileName())"
        var candidate = directory.appendingPathComponent("\(baseName).zip")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix).zip")
            suffix += 1
        }
        return candidate
    }

    private func validatedBackupRoot(in extractionURL: URL) throws -> URL {
        if fileManager.fileExists(
            atPath: extractionURL.appendingPathComponent(Path.manifest).path
        ) {
            try validateBackupRoot(extractionURL)
            return extractionURL
        }

        let children = try fileManager.contentsOfDirectory(
            at: extractionURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        let directoryChildren = try children.filter { child in
            try resourceValues(for: child).isDirectory == true
        }
        guard directoryChildren.count == 1,
              fileManager.fileExists(
                atPath: directoryChildren[0]
                    .appendingPathComponent(Path.manifest)
                    .path
              ) else {
            throw HistoryBackupError.missingManifest
        }

        try validateBackupRoot(directoryChildren[0])
        return directoryChildren[0]
    }

    private func validateBackupRoot(_ root: URL) throws {
        let manifestURL = root.appendingPathComponent(Path.manifest)
        try requireRegularFile(manifestURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest: BackupManifest
        do {
            manifest = try decoder.decode(
                BackupManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw HistoryBackupError.invalidManifest
        }
        guard manifest.kind == BackupManifest.archiveKind else {
            throw HistoryBackupError.invalidManifest
        }
        guard manifest.schemaVersion == BackupManifest.currentSchemaVersion else {
            throw HistoryBackupError.unsupportedSchemaVersion(manifest.schemaVersion)
        }

        let allowedTopLevelPaths = Set([
            Path.manifest,
            Path.database,
            Path.images,
            Path.text
        ])
        let topLevelChildren = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ]
        )
        let unexpectedPaths = Set(topLevelChildren.map(\.lastPathComponent))
            .subtracting(allowedTopLevelPaths)
        guard unexpectedPaths.isEmpty else {
            throw HistoryBackupError.invalidArchiveLayout(
                "Unexpected top-level paths: \(unexpectedPaths.sorted().joined(separator: ", "))"
            )
        }

        try requireRegularFile(root.appendingPathComponent(Path.database))
        try requireDirectory(root.appendingPathComponent(Path.images, isDirectory: true))
        try requireDirectory(root.appendingPathComponent(Path.text, isDirectory: true))
        try requireFlatRegularFiles(
            in: root.appendingPathComponent(Path.images, isDirectory: true)
        )
        try requireFlatRegularFiles(
            in: root.appendingPathComponent(Path.text, isDirectory: true)
        )
    }

    private func requireRegularFile(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw HistoryBackupError.invalidArchiveLayout(
                "\(url.lastPathComponent) is missing"
            )
        }
        let values = try resourceValues(for: url)
        guard values.isSymbolicLink != true,
              values.isRegularFile == true else {
            throw HistoryBackupError.invalidArchiveLayout(
                "\(url.lastPathComponent) must be a regular file"
            )
        }
    }

    private func requireDirectory(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw HistoryBackupError.invalidArchiveLayout(
                "\(url.lastPathComponent) is missing"
            )
        }
        let values = try resourceValues(for: url)
        guard values.isSymbolicLink != true,
              values.isDirectory == true else {
            throw HistoryBackupError.invalidArchiveLayout(
                "\(url.lastPathComponent) must be a directory"
            )
        }
    }

    private func requireFlatRegularFiles(in directoryURL: URL) throws {
        let children = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ]
        )
        for child in children {
            let values = try resourceValues(for: child)
            guard values.isSymbolicLink != true,
                  values.isRegularFile == true else {
                throw HistoryBackupError.invalidArchiveLayout(
                    "\(directoryURL.lastPathComponent)/\(child.lastPathComponent) must be a regular file"
                )
            }
        }
    }

    private func resourceValues(for url: URL) throws -> URLResourceValues {
        try url.resourceValues(
            forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ]
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent(
                "PastePilotBackup-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func timestampForFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private func runDitto(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let details: String
            if let message, !message.isEmpty {
                details = message
            } else {
                details = "ditto exited with \(process.terminationStatus)"
            }
            throw HistoryBackupError.archiveCommandFailed(
                details
            )
        }
    }
}
