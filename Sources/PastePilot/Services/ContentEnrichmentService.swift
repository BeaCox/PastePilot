import CoreGraphics
import Darwin
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

private final class LinkMetadataRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        if let targetURL = request.url,
           URLSessionLinkMetadataService.isEligible(targetURL) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}

final class URLSessionLinkMetadataService: LinkMetadataService, @unchecked Sendable {
    private static let maximumResponseByteCount = 1_048_576
    private static let redirectDelegate = LinkMetadataRedirectDelegate()
    private static let sensitiveQueryParameterNames: Set<String> = [
        "token", "access_token", "auth", "key", "api_key", "apikey",
        "secret", "password", "passwd", "sig", "signature",
        "x-amz-signature", "x-amz-credential"
    ]
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

        guard let (bytes, response) = try? await session.bytes(
            for: request,
            delegate: Self.redirectDelegate
        ),
              let response = response as? HTTPURLResponse,
              (200..<400).contains(response.statusCode),
              response.mimeType?.lowercased().contains("html") == true else {
            return nil
        }

        var data = Data()
        data.reserveCapacity(min(16_384, Self.maximumResponseByteCount))
        do {
            for try await byte in bytes {
                guard data.count < Self.maximumResponseByteCount else {
                    return nil
                }
                data.append(byte)
                if byte == UInt8(ascii: ">"),
                   data.count >= 7,
                   String(decoding: data.suffix(12), as: UTF8.self)
                    .lowercased()
                    .contains("</head>") {
                    break
                }
            }
        } catch {
            return nil
        }

        guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }

        let resolvedURL = response.url ?? url
        guard Self.isEligible(resolvedURL) else { return nil }
        return LinkMetadataHTMLParser.metadata(from: html, resolvedURL: resolvedURL)
    }

    static func isEligible(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let rawHost = url.host,
              !rawHost.isEmpty,
              url.user == nil,
              url.password == nil,
              !isPrivateOrLocalHost(rawHost),
              !hasSensitiveQueryParameter(url) else {
            return false
        }
        return true
    }

    private static func hasSensitiveQueryParameter(_ url: URL) -> Bool {
        guard let queryItems = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems else {
            return false
        }
        return queryItems.contains { item in
            sensitiveQueryParameterNames.contains(item.name.lowercased())
        }
    }

    private static func isPrivateOrLocalHost(_ rawHost: String) -> Bool {
        var host = rawHost.lowercased()
        while host.hasSuffix(".") {
            host.removeLast()
        }
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        if let zoneIndex = host.firstIndex(of: "%") {
            host = String(host[..<zoneIndex])
        }

        if host.isEmpty
            || host == "localhost"
            || host.hasSuffix(".localhost")
            || host.hasSuffix(".local")
            || host.hasSuffix(".internal") {
            return true
        }

        var ipv4 = in_addr()
        if inet_pton(AF_INET, host, &ipv4) == 1 {
            return isDisallowedIPv4(UInt32(bigEndian: ipv4.s_addr))
        }

        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, host, &ipv6) == 1 {
            return isDisallowedIPv6(ipv6)
        }

        return false
    }

    private static func isDisallowedIPv4(_ ip: UInt32) -> Bool {
        if (ip & 0xFF00_0000) == 0x0000_0000 { return true } // 0.0.0.0/8
        if (ip & 0xFF00_0000) == 0x0A00_0000 { return true } // 10.0.0.0/8
        if (ip & 0xFFC0_0000) == 0x6440_0000 { return true } // 100.64.0.0/10
        if (ip & 0xFF00_0000) == 0x7F00_0000 { return true } // 127.0.0.0/8
        if (ip & 0xFFFF_0000) == 0xA9FE_0000 { return true } // 169.254.0.0/16
        if (ip & 0xFFF0_0000) == 0xAC10_0000 { return true } // 172.16.0.0/12
        if (ip & 0xFFFF_0000) == 0xC0A8_0000 { return true } // 192.168.0.0/16
        if ip >= 0xE000_0000 { return true }                 // 224.0.0.0/4+
        return false
    }

    private static func isDisallowedIPv6(_ address: in6_addr) -> Bool {
        var copy = address
        return withUnsafeBytes(of: &copy) { bytes -> Bool in
            let isAllZeroPrefix = (0..<15).allSatisfy { bytes[$0] == 0 }
            if isAllZeroPrefix && (bytes[15] == 0 || bytes[15] == 1) {
                return true // :: and ::1
            }
            if (bytes[0] & 0xFE) == 0xFC { return true } // fc00::/7 unique local
            if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 { return true } // fe80::/10 link-local
            if bytes[0] == 0xFF { return true } // ff00::/8 multicast

            let isIPv4Mapped = (0..<10).allSatisfy { bytes[$0] == 0 }
                && bytes[10] == 0xFF && bytes[11] == 0xFF
            if isIPv4Mapped {
                let ipv4 = (UInt32(bytes[12]) << 24)
                    | (UInt32(bytes[13]) << 16)
                    | (UInt32(bytes[14]) << 8)
                    | UInt32(bytes[15])
                return isDisallowedIPv4(ipv4)
            }
            return false
        }
    }
}

enum LinkMetadataHTMLParser {
    private static let metaExpression = RegexFactory.make(
        #"<meta\b[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let attributeExpression = RegexFactory.make(
        #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*([\"'])(.*?)\2"#,
        options: [.dotMatchesLineSeparators]
    )
    private static let titleExpression = RegexFactory.make(
        #"<title\b[^>]*>(.*?)</title\s*>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let stripTagsExpression = RegexFactory.make(#"<[^>]+>"#)

    static func metadata(from html: String, resolvedURL: URL) -> LinkMetadata? {
        let meta = metaAttributes(in: html)
        let title = normalized(
            meta["property:og:title"]
                ?? meta["name:twitter:title"]
                ?? firstMatch(in: html, expression: titleExpression),
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
        guard let metaExpression, let attributeExpression else {
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

    private static func firstMatch(
        in text: String,
        expression: NSRegularExpression?
    ) -> String? {
        guard let expression else { return nil }
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
        let withoutTags: String
        if let stripTagsExpression {
            let range = NSRange(value.startIndex..., in: value)
            withoutTags = stripTagsExpression.stringByReplacingMatches(
                in: value,
                range: range,
                withTemplate: " "
            )
        } else {
            withoutTags = value
        }
        let decoded = HTMLPlainTextExtractor.decodeHTMLEntities(in: withoutTags)
        let collapsed = decoded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(limit))
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
