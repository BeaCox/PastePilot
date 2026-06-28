import Foundation

struct PastePilotNotice: Equatable, Sendable {
    enum Style: Sendable {
        case success
        case warning
        case error
    }

    let message: String
    let style: Style

    init(_ message: String, style: Style = .success) {
        self.message = message
        self.style = style
    }

    var systemImage: String {
        switch style {
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .error:
            "xmark.circle.fill"
        }
    }
}

protocol PastePilotNoticePosting: Sendable {
    func post(_ notice: PastePilotNotice)
}

struct NotificationCenterPastePilotNoticePoster: PastePilotNoticePosting {
    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func post(_ notice: PastePilotNotice) {
        notificationCenter.postPastePilotNotice(notice)
    }
}

extension Notification.Name {
    static let pastePilotNotice = Notification.Name("PastePilotNotice")
}

extension NotificationCenter {
    func postPastePilotNotice(_ notice: PastePilotNotice) {
        if Thread.isMainThread {
            post(name: .pastePilotNotice, object: notice)
        } else {
            DispatchQueue.main.async {
                self.post(name: .pastePilotNotice, object: notice)
            }
        }
    }
}
