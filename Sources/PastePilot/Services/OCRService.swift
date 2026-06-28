import CoreGraphics
import Vision

protocol OCRService: Sendable {
    func recognizeText(
        in image: CGImage,
        recognitionMode: OCRRecognitionMode,
        languageMode: OCRLanguageMode
    ) async -> String?
}

struct VisionOCRService: OCRService {
    func recognizeText(
        in image: CGImage,
        recognitionMode: OCRRecognitionMode,
        languageMode: OCRLanguageMode
    ) async -> String? {
        guard recognitionMode != .off else { return nil }

        return await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = recognitionMode == .fast ? .fast : .accurate
            request.recognitionLanguages = Self.recognitionLanguages(for: languageMode)
            request.usesLanguageCorrection = recognitionMode == .accurate

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try? handler.perform([request])

            let text = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            return text.isEmpty ? nil : text
        }.value
    }

    private static func recognitionLanguages(for mode: OCRLanguageMode) -> [String] {
        switch mode {
        case .system:
            let preferredIdentifier = Locale.preferredLanguages.first ?? "en-US"
            return [preferredIdentifier]
        case .english:
            return ["en-US"]
        case .multilingual:
            return ["zh-Hans", "zh-Hant", "en-US", "ja", "ko"]
        }
    }
}
