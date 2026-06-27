import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PastePilot

func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PastePilotTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory
}

@MainActor
func waitForCapturedItem(
    in store: ClipboardStore,
    matching predicate: (ClipboardItem) -> Bool = { _ in true }
) async throws -> ClipboardItem {
    for _ in 0..<100 {
        if let item = store.items.first(where: predicate) {
            return item
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    let matchingItem = store.items.first(where: predicate)
    return try #require(matchingItem)
}

func makeTestImage(width: Int, height: Int) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = try #require(
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    context.setFillColor(NSColor.systemBlue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

struct StubOCRService: OCRService {
    var result: String?

    init(result: String? = nil) {
        self.result = result
    }

    func recognizeText(
        in image: CGImage,
        recognitionMode: OCRRecognitionMode,
        languageMode: OCRLanguageMode
    ) async -> String? {
        result
    }
}

struct DelayedStubOCRService: OCRService {
    var result: String?
    var delayNanoseconds: UInt64

    func recognizeText(
        in image: CGImage,
        recognitionMode: OCRRecognitionMode,
        languageMode: OCRLanguageMode
    ) async -> String? {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        return result
    }
}

struct SilentPastePilotLogger: PastePilotLogging {
    func log(_ message: String) {}
}

final class CapturingNoticePoster: PastePilotNoticePosting {
    private let lock = NSLock()
    private var recordedNotices: [PastePilotNotice] = []

    var notices: [PastePilotNotice] {
        lock.lock()
        defer { lock.unlock() }
        return recordedNotices
    }

    func post(_ notice: PastePilotNotice) {
        lock.lock()
        recordedNotices.append(notice)
        lock.unlock()
    }
}

enum StubCaptureResult {
    case timeout
    case payload(ClipboardCaptureSnapshot.Payload?)
}

final class StubClipboardCaptureQueue: ClipboardCapturing {
    private var results: [StubCaptureResult]
    private(set) var captureCalls = 0

    init(results: [StubCaptureResult]) {
        self.results = results
    }

    func capture(
        pasteboard: NSPasteboard,
        changeCount: Int,
        completion: @escaping (ClipboardCaptureSnapshot?) -> Void
    ) {
        captureCalls += 1
        guard !results.isEmpty else {
            completion(nil)
            return
        }
        switch results.removeFirst() {
        case .timeout:
            completion(nil)
        case .payload(let payload):
            completion(ClipboardCaptureSnapshot(
                changeCount: changeCount,
                sourceAppName: nil,
                sourceBundleIdentifier: nil,
                payload: payload
            ))
        }
    }
}
