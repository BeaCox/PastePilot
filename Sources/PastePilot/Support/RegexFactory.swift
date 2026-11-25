import Foundation

enum RegexFactory {
    static func make(
        _ pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            NSLog("PastePilot failed to compile regex '\(pattern)': \(error)")
            return nil
        }
    }
}

final class BoundedRegexCache: @unchecked Sendable {
    private struct Key: Hashable {
        let pattern: String
        let optionsRawValue: UInt
    }

    private let lock = NSLock()
    private let capacity: Int
    private var storage: [Key: NSRegularExpression] = [:]
    private var insertionOrder: [Key] = []

    init(capacity: Int = 256) {
        self.capacity = max(1, capacity)
    }

    func regex(
        for pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression? {
        let key = Key(pattern: pattern, optionsRawValue: options.rawValue)
        if let cached = lock.withLock({ storage[key] }) {
            return cached
        }
        guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        lock.withLock {
            if storage[key] == nil {
                if insertionOrder.count >= capacity, !insertionOrder.isEmpty {
                    let evicted = insertionOrder.removeFirst()
                    storage.removeValue(forKey: evicted)
                }
                storage[key] = compiled
                insertionOrder.append(key)
            }
        }
        return compiled
    }
}
