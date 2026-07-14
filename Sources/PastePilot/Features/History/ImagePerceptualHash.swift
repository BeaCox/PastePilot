import CoreGraphics
import Foundation

enum ImagePerceptualHash {
    private static let sampleWidth = 9
    private static let sampleHeight = 8
    private static let version = "v1"
    private static let maximumHammingDistance = 5
    private static let maximumLuminanceDistance = 24

    static func signature(for image: CGImage) -> String? {
        var pixels = [UInt8](
            repeating: 0,
            count: sampleWidth * sampleHeight
        )
        guard let context = CGContext(
            data: &pixels,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: sampleWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight)
        )

        var differenceHash: UInt64 = 0
        for row in 0..<sampleHeight {
            for column in 0..<(sampleWidth - 1) {
                differenceHash <<= 1
                let offset = row * sampleWidth + column
                if pixels[offset] > pixels[offset + 1] {
                    differenceHash |= 1
                }
            }
        }
        let averageLuminance = pixels.reduce(0) { $0 + Int($1) } / pixels.count
        return String(
            format: "%@-%016llx-%02x",
            version,
            differenceHash,
            averageLuminance
        )
    }

    static func areSimilar(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = parsed(lhs), let rhs = parsed(rhs) else { return false }
        return (lhs.hash ^ rhs.hash).nonzeroBitCount <= maximumHammingDistance
            && abs(lhs.luminance - rhs.luminance) <= maximumLuminanceDistance
    }

    private static func parsed(
        _ signature: String?
    ) -> (hash: UInt64, luminance: Int)? {
        guard let components = signature?.split(separator: "-"),
              components.count == 3,
              components[0] == Substring(version),
              let hash = UInt64(components[1], radix: 16),
              let luminance = Int(components[2], radix: 16) else {
            return nil
        }
        return (hash, luminance)
    }
}
