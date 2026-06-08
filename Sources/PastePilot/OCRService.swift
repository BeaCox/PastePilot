import CoreGraphics
import Vision

protocol OCRService {
    func recognizeText(in image: CGImage) async -> String?
}

struct VisionOCRService: OCRService {
    func recognizeText(in image: CGImage) async -> String? {
        await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja", "ko"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try? handler.perform([request])

            let text = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            return text.isEmpty ? nil : text
        }.value
    }
}
