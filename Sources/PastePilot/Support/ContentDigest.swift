import CryptoKit
import Foundation

enum ContentDigest {
    static func sha256Hex(for string: String) -> String {
        sha256Hex(for: Data(string.utf8))
    }

    static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
