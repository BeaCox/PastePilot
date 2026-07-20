import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum ProtectedHistoryError: LocalizedError {
    case authenticationUnavailable
    case keychain(OSStatus)
    case locked
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .authenticationUnavailable:
            "This Mac cannot authenticate access to protected history.".localized
        case let .keychain(status):
            "Keychain error (%d).".localized(Int(status))
        case .locked:
            "Protected history is locked.".localized
        case .invalidPayload:
            "Protected history data is invalid.".localized
        }
    }
}

protocol ProtectedHistoryKeyStoring: Sendable {
    func loadOrCreateKey() throws -> Data
}

struct KeychainProtectedHistoryKeyStore: ProtectedHistoryKeyStoring {
    private let service = "com.beacox.PastePilot.protected-history"
    private let account = "encryption-key-v1"

    func loadOrCreateKey() throws -> Data {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data, data.count == 32 else {
                throw ProtectedHistoryError.invalidPayload
            }
            return data
        }
        guard status == errSecItemNotFound else {
            throw ProtectedHistoryError.keychain(status)
        }

        var key = Data(count: 32)
        let randomStatus = key.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw ProtectedHistoryError.keychain(randomStatus)
        }
        let addition: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let addStatus = SecItemAdd(addition as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            return try loadOrCreateKey()
        }
        guard addStatus == errSecSuccess else {
            throw ProtectedHistoryError.keychain(addStatus)
        }
        return key
    }
}

final class ProtectedHistoryVault: @unchecked Sendable {
    private let keyStore: any ProtectedHistoryKeyStoring
    private let lock = NSLock()
    private var keyData: Data?
    private var expiresAt: Date?

    init(keyStore: any ProtectedHistoryKeyStoring = KeychainProtectedHistoryKeyStore()) {
        self.keyStore = keyStore
    }

    var isUnlocked: Bool {
        lock.withLock {
            discardExpiredKey()
            return keyData != nil
        }
    }

    func unlock(timeout: TimeInterval) throws {
        let key = try keyStore.loadOrCreateKey()
        guard key.count == 32 else { throw ProtectedHistoryError.invalidPayload }
        lock.withLock {
            keyData = key
            expiresAt = timeout > 0 ? Date().addingTimeInterval(timeout) : nil
        }
    }

    func lockVault() {
        lock.withLock {
            keyData = nil
            expiresAt = nil
        }
    }

    func encrypt(_ plaintext: Data) throws -> Data {
        let key = try symmetricKey()
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw ProtectedHistoryError.invalidPayload
        }
        return combined
    }

    func decrypt(_ ciphertext: Data) throws -> Data {
        let key = try symmetricKey()
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw ProtectedHistoryError.invalidPayload
        }
    }

    private func symmetricKey() throws -> SymmetricKey {
        try lock.withLock {
            discardExpiredKey()
            guard let keyData else { throw ProtectedHistoryError.locked }
            return SymmetricKey(data: keyData)
        }
    }

    private func discardExpiredKey() {
        guard let expiresAt, expiresAt <= Date() else { return }
        keyData = nil
        self.expiresAt = nil
    }
}

struct ProtectedHistoryAuthenticator {
    func authenticate() async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? ProtectedHistoryError.authenticationUnavailable
        }
        try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock protected PastePilot history".localized
        )
    }
}
