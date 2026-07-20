import Foundation

struct PastePilotNotice: Equatable, Sendable {
    enum Style: Sendable {
        case success
        case warning
        case error
    }

    enum Action: Equatable, Sendable {
        case undoDelete(UUID)
    }

    let message: String
    let style: Style
    var action: Action?

    init(_ message: String, style: Style = .success, action: Action? = nil) {
        self.message = message
        self.style = style
        self.action = action
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
