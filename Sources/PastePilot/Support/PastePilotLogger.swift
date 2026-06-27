import Foundation

protocol PastePilotLogging: Sendable {
    func log(_ message: String)
}

struct NSLogPastePilotLogger: PastePilotLogging {
    func log(_ message: String) {
        NSLog("%@", message)
    }
}
