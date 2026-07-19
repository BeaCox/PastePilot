import Foundation

@MainActor
final class PasteStackController: ObservableObject {
    enum StartResult: Equatable {
        case started
        case empty
        case alreadyPasting
        case accessibilityRequired
    }

    static let maximumItemCount = 50

    @Published private(set) var itemIDs: [UUID] = []
    @Published private(set) var isPasting = false
    @Published private(set) var completedItemCount = 0

    private let isAccessibilityGranted: @MainActor () -> Bool
    private let postPasteShortcut: @MainActor () -> Void
    private let sleep: @MainActor (Duration) async -> Void
    private let focusDelay: Duration
    private let pasteDelay: Duration
    private let interPasteDelay: Duration
    private var pasteTask: Task<Void, Never>?
    private var runToken: UUID?

    init(
        isAccessibilityGranted: @escaping @MainActor () -> Bool = {
            EventPostingPermission.isGranted
        },
        postPasteShortcut: @escaping @MainActor () -> Void = {
            PasteShortcutService.postCommandV()
        },
        sleep: @escaping @MainActor (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        },
        focusDelay: Duration = .milliseconds(180),
        pasteDelay: Duration = .milliseconds(80),
        interPasteDelay: Duration = .milliseconds(180)
    ) {
        self.isAccessibilityGranted = isAccessibilityGranted
        self.postPasteShortcut = postPasteShortcut
        self.sleep = sleep
        self.focusDelay = focusDelay
        self.pasteDelay = pasteDelay
        self.interPasteDelay = interPasteDelay
    }

    deinit {
        pasteTask?.cancel()
    }

    var count: Int {
        itemIDs.count
    }

    func contains(_ id: UUID) -> Bool {
        itemIDs.contains(id)
    }

    func position(of id: UUID) -> Int? {
        itemIDs.firstIndex(of: id).map { $0 + 1 }
    }

    @discardableResult
    func toggle(_ id: UUID) -> Bool {
        guard !isPasting else { return contains(id) }
        if let index = itemIDs.firstIndex(of: id) {
            itemIDs.remove(at: index)
            return false
        }
        guard itemIDs.count < Self.maximumItemCount else { return false }
        itemIDs.append(id)
        return true
    }

    func retain(availableIDs: Set<UUID>) {
        guard !isPasting else { return }
        itemIDs.removeAll { !availableIDs.contains($0) }
    }

    func clear() {
        guard !isPasting else { return }
        itemIDs.removeAll(keepingCapacity: false)
        completedItemCount = 0
    }

    @discardableResult
    func start(
        items: [ClipboardItem],
        separator: String,
        copyItem: @escaping @MainActor (ClipboardItem) -> Bool,
        copySeparator: @escaping @MainActor (String) -> Void
    ) -> StartResult {
        guard !isPasting else { return .alreadyPasting }
        guard !items.isEmpty else { return .empty }
        guard isAccessibilityGranted() else { return .accessibilityRequired }

        let token = UUID()
        runToken = token
        isPasting = true
        completedItemCount = 0
        pasteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await sleep(focusDelay)
            guard !Task.isCancelled else {
                finishCancelledRun(token: token)
                return
            }

            for (index, item) in items.enumerated() {
                guard await pastePayload({ copyItem(item) }) else {
                    if Task.isCancelled {
                        finishCancelledRun(token: token)
                        return
                    }
                    continue
                }
                completedItemCount += 1

                if index < items.count - 1, !separator.isEmpty {
                    guard await pastePayload({
                        copySeparator(separator)
                        return true
                    }) else {
                        finishCancelledRun(token: token)
                        return
                    }
                }
            }

            finishCompletedRun(token: token)
        }
        return .started
    }

    func cancel() {
        guard isPasting else { return }
        pasteTask?.cancel()
        pasteTask = nil
        runToken = nil
        isPasting = false
        completedItemCount = 0
    }

    func waitForPendingPaste() async {
        await pasteTask?.value
    }

    private func pastePayload(_ copy: @MainActor () -> Bool) async -> Bool {
        guard !Task.isCancelled, copy() else { return false }
        await sleep(pasteDelay)
        guard !Task.isCancelled else { return false }
        postPasteShortcut()
        await sleep(interPasteDelay)
        return !Task.isCancelled
    }

    private func finishCompletedRun(token: UUID) {
        guard runToken == token else { return }
        pasteTask = nil
        runToken = nil
        isPasting = false
        itemIDs.removeAll(keepingCapacity: false)
    }

    private func finishCancelledRun(token: UUID) {
        guard runToken == token else { return }
        pasteTask = nil
        runToken = nil
        isPasting = false
        completedItemCount = 0
    }
}
