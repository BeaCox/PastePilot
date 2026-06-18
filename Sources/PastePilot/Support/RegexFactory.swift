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
