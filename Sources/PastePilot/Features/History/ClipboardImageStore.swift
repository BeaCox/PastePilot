import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ClipboardImageStore {
    let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func image(fileName: String) -> NSImage? {
        NSImage(contentsOf: url(fileName: fileName))
    }

    func thumbnail(fileName: String, pointSize: CGFloat) -> NSImage? {
        guard let image = image(fileName: fileName) else { return nil }
        let size = NSSize(width: pointSize, height: pointSize)
        let thumbnail = NSImage(size: size)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let sourceSize = image.size
        let scale = max(
            size.width / max(sourceSize.width, 1),
            size.height / max(sourceSize.height, 1)
        )
        let drawSize = NSSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        let drawRect = NSRect(
            x: (size.width - drawSize.width) / 2,
            y: (size.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect)
        thumbnail.unlockFocus()
        return thumbnail
    }

    func path(fileName: String) -> String {
        url(fileName: fileName).path
    }

    func byteCount(fileName: String) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: url(fileName: fileName).path
        )
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    func save(_ data: Data, fileName: String) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try data.write(to: url(fileName: fileName), options: .atomic)
    }

    func delete(fileName: String) {
        try? FileManager.default.removeItem(at: url(fileName: fileName))
    }

    func removeOrphans(retaining fileNames: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for file in files where !fileNames.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func url(fileName: String) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }
}

struct ProcessedClipboardImage {
    let fileName: String
    let byteCount: Int
    let digest: String
    let width: Int
    let height: Int
}

enum ClipboardImageProcessingError: Error {
    case encodingFailed
    case exceedsSizeLimit
}

final class ClipboardImageProcessingQueue: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "PastePilot.ImageProcessingQueue",
        qos: .userInitiated
    )

    func encodeAndSave(
        _ image: CGImage,
        fileName: String,
        imageStore: ClipboardImageStore,
        sizeLimitBytes: Int,
        completion: @escaping @Sendable (Result<ProcessedClipboardImage, Error>) -> Void
    ) {
        queue.async {
            do {
                guard let pngData = Self.pngData(for: image) else {
                    completion(.failure(ClipboardImageProcessingError.encodingFailed))
                    return
                }
                guard pngData.count <= sizeLimitBytes else {
                    completion(.failure(ClipboardImageProcessingError.exceedsSizeLimit))
                    return
                }

                try imageStore.save(pngData, fileName: fileName)
                let digest = ContentDigest.sha256Hex(for: pngData)
                completion(
                    .success(
                        ProcessedClipboardImage(
                            fileName: fileName,
                            byteCount: pngData.count,
                            digest: digest,
                            width: image.width,
                            height: image.height
                        )
                    )
                )
            } catch {
                completion(.failure(error))
            }
        }
    }

    private static func pngData(for image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}
