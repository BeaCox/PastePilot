import CoreGraphics
import Foundation
import Vision

struct LinkMetadata: Codable, Equatable, Sendable {
    let title: String?
    let summary: String?
    let siteName: String?
    let resolvedURL: String
}

protocol LinkMetadataService: Sendable {
    func metadata(for url: URL) async -> LinkMetadata?
}

final class URLSessionLinkMetadataService: LinkMetadataService, @unchecked Sendable {
    private static let maximumResponseByteCount = 1_048_576
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    func metadata(for url: URL) async -> LinkMetadata? {
        guard Self.isEligible(url) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(
            "bytes=0-\(Self.maximumResponseByteCount - 1)",
            forHTTPHeaderField: "Range"
        )

        guard let (data, response) = try? await session.data(for: request),
              data.count <= Self.maximumResponseByteCount,
              let response = response as? HTTPURLResponse,
              (200..<400).contains(response.statusCode),
              response.mimeType?.lowercased().contains("html") == true,
              let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }

        let resolvedURL = response.url ?? url
        return LinkMetadataHTMLParser.metadata(from: html, resolvedURL: resolvedURL)
    }

    static func isEligible(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host?.isEmpty == false,
              url.user == nil,
              url.password == nil else {
            return false
        }
        return true
    }
}

enum LinkMetadataHTMLParser {
    static func metadata(from html: String, resolvedURL: URL) -> LinkMetadata? {
        let meta = metaAttributes(in: html)
        let title = normalized(
            meta["property:og:title"]
                ?? meta["name:twitter:title"]
                ?? firstMatch(
                    in: html,
                    pattern: #"<title\b[^>]*>(.*?)</title\s*>"#
                ),
            limit: 300
        )
        let summary = normalized(
            meta["property:og:description"]
                ?? meta["name:twitter:description"]
                ?? meta["name:description"],
            limit: 1_000
        )
        let siteName = normalized(meta["property:og:site_name"], limit: 200)

        guard title != nil || summary != nil || siteName != nil else { return nil }
        return LinkMetadata(
            title: title,
            summary: summary,
            siteName: siteName,
            resolvedURL: resolvedURL.absoluteString
        )
    }

    private static func metaAttributes(in html: String) -> [String: String] {
        guard let metaExpression = try? NSRegularExpression(
            pattern: #"<meta\b[^>]*>"#,
            options: [.caseInsensitive]
        ), let attributeExpression = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*([\"'])(.*?)\2"#,
            options: [.dotMatchesLineSeparators]
        ) else {
            return [:]
        }

        let nsHTML = html as NSString
        let metaTags = metaExpression.matches(
            in: html,
            range: NSRange(location: 0, length: nsHTML.length)
        )
        var values: [String: String] = [:]
        for match in metaTags {
            let tag = nsHTML.substring(with: match.range)
            let nsTag = tag as NSString
            let attributes = attributeExpression.matches(
                in: tag,
                range: NSRange(location: 0, length: nsTag.length)
            ).reduce(into: [String: String]()) { result, attribute in
                guard attribute.numberOfRanges >= 4 else { return }
                let name = nsTag.substring(with: attribute.range(at: 1)).lowercased()
                result[name] = nsTag.substring(with: attribute.range(at: 3))
            }
            guard let content = attributes["content"] else { continue }
            if let property = attributes["property"]?.lowercased() {
                values["property:\(property)"] = content
            }
            if let name = attributes["name"]?.lowercased() {
                values["name:\(name)"] = content
            }
        }
        return values
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let nsText = text as NSString
        guard let match = expression.firstMatch(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ), match.numberOfRanges > 1 else {
            return nil
        }
        return nsText.substring(with: match.range(at: 1))
    }

    private static func normalized(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let withoutTags = value.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        let decoded = decodeHTMLEntities(in: withoutTags)
        let collapsed = decoded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(limit))
    }

    private static func decodeHTMLEntities(in value: String) -> String {
        var decoded = value
        let namedEntities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&apos;": "'", "&nbsp;": " "
        ]
        for (entity, replacement) in namedEntities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        guard let expression = try? NSRegularExpression(
            pattern: #"&#(x[0-9A-Fa-f]+|[0-9]+);"#
        ) else {
            return decoded
        }
        let matches = expression.matches(
            in: decoded,
            range: NSRange(decoded.startIndex..., in: decoded)
        ).reversed()
        for match in matches {
            guard let wholeRange = Range(match.range(at: 0), in: decoded),
                  let valueRange = Range(match.range(at: 1), in: decoded) else {
                continue
            }
            let encodedValue = String(decoded[valueRange])
            let radix = encodedValue.lowercased().hasPrefix("x") ? 16 : 10
            let digits = radix == 16 ? String(encodedValue.dropFirst()) : encodedValue
            guard let scalarValue = UInt32(digits, radix: radix),
                  let scalar = UnicodeScalar(scalarValue) else {
                continue
            }
            decoded.replaceSubrange(wholeRange, with: String(Character(scalar)))
        }
        return decoded
    }
}

struct DetectedBarcode: Codable, Equatable, Hashable, Sendable {
    let payload: String
    let symbology: String
}

enum DetectedBarcodePolicy {
    static let maximumCount = 20
    static let maximumPayloadCharacterCount = 4_096
    static let maximumTotalByteCount = 32 * 1_024

    static func retained(_ barcodes: [DetectedBarcode]) -> [DetectedBarcode] {
        var retained: [DetectedBarcode] = []
        var seen = Set<String>()
        var totalByteCount = 0
        for barcode in barcodes {
            let payload = barcode.payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !payload.isEmpty, seen.insert(payload).inserted else { continue }
            let clippedPayload = String(payload.prefix(maximumPayloadCharacterCount))
            let byteCount = clippedPayload.utf8.count
            guard totalByteCount + byteCount <= maximumTotalByteCount else { break }
            retained.append(
                DetectedBarcode(payload: clippedPayload, symbology: barcode.symbology)
            )
            totalByteCount += byteCount
            if retained.count == maximumCount { break }
        }
        return retained
    }
}

protocol BarcodeDetectionService: Sendable {
    func detectBarcodes(in image: CGImage) async -> [DetectedBarcode]
}

struct VisionBarcodeDetectionService: BarcodeDetectionService {
    func detectBarcodes(in image: CGImage) async -> [DetectedBarcode] {
        await Task.detached(priority: .utility) {
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try? handler.perform([request])

            var seen = Set<String>()
            let detected: [DetectedBarcode] = (request.results ?? []).compactMap {
                observation in
                guard let payload = observation.payloadStringValue?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !payload.isEmpty,
                    seen.insert(payload).inserted else {
                    return nil
                }
                return DetectedBarcode(
                    payload: payload,
                    symbology: observation.symbology.rawValue
                )
            }
            return DetectedBarcodePolicy.retained(detected)
        }.value
    }
}
