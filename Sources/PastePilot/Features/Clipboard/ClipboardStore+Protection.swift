import Foundation

extension ClipboardStore {
    var hasProtectedItems: Bool {
        items.contains(where: \.isProtected)
    }

    var hasLockedProtectedItems: Bool {
        items.contains { $0.protectionState == .locked }
    }

    func canProtect(_ item: ClipboardItem) -> Bool {
        !item.isProtected && item.kind != .image && item.kind != .file
    }

    @discardableResult
    func unlockProtectedHistory() async -> Bool {
        do {
            try await authenticateAndUnlockProtectedHistory()
            reloadItemsForProtectionState()
            noticePoster.post(PastePilotNotice(
                "Protected history unlocked".localized,
                style: .success
            ))
            return true
        } catch {
            logger.log("PastePilot could not unlock protected history: \(error)")
            noticePoster.post(PastePilotNotice(
                "Protected history could not be unlocked".localized,
                style: .error
            ))
            return false
        }
    }

    func lockProtectedHistory(postsNotice: Bool = true) {
        historyWriteQueue.flush()
        protectedHistoryVault.lockVault()
        reloadItemsForProtectionState()
        protectedHistoryLockTask?.cancel()
        protectedHistoryLockTask = nil
        if postsNotice {
            noticePoster.post(PastePilotNotice("Protected history locked".localized))
        }
    }

    @discardableResult
    func protect(_ id: UUID) async -> Bool {
        guard let original = items.first(where: { $0.id == id }),
              canProtect(original),
              let fullContent = content(for: original) else {
            return false
        }
        let wasUnlocked = protectedHistoryVault.isUnlocked
        do {
            if !protectedHistoryVault.isUnlocked {
                try await authenticateAndUnlockProtectedHistory()
            }
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                if !wasUnlocked {
                    lockProtectedHistory(postsNotice: false)
                }
                return false
            }
            historyWriteQueue.flush()
            items[index] = original.preparedForProtection(content: fullContent)
            do {
                try historyRepository.save(items)
            } catch {
                items[index] = original
                throw error
            }
            deleteTextFile(for: original)
            do {
                try historyRepository.securelyCompactDatabase()
            } catch {
                logger.log(
                    "PastePilot protected an item but could not compact old database pages: \(error)"
                )
            }
            lockProtectedHistory(postsNotice: false)
            noticePoster.post(PastePilotNotice(
                "Item protected and locked".localized,
                style: .success
            ))
            return true
        } catch {
            if !wasUnlocked, protectedHistoryVault.isUnlocked {
                lockProtectedHistory(postsNotice: false)
            }
            logger.log("PastePilot could not protect history item: \(error)")
            noticePoster.post(PastePilotNotice(
                "Item could not be protected".localized,
                style: .error
            ))
            return false
        }
    }

    @discardableResult
    func removeProtection(_ id: UUID) async -> Bool {
        guard items.contains(where: { $0.id == id && $0.isProtected }) else {
            return false
        }
        if !protectedHistoryVault.isUnlocked,
           !(await unlockProtectedHistory()) {
            return false
        }
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].protectionState == .unlocked else {
            return false
        }
        items[index].protectionState = nil
        _ = externalizeLoadedLargeTextContent()
        save()
        historyWriteQueue.flush()
        noticePoster.post(PastePilotNotice(
            "Item removed from protected storage".localized,
            style: .success
        ))
        return true
    }

    private func authenticateAndUnlockProtectedHistory() async throws {
        try await ProtectedHistoryAuthenticator().authenticate()
        try protectedHistoryVault.unlock(
            timeout: TimeInterval(settings.protectedHistoryUnlockTimeoutSeconds)
        )
        scheduleProtectedHistoryLock()
    }

    private func scheduleProtectedHistoryLock() {
        protectedHistoryLockTask?.cancel()
        let timeout = settings.protectedHistoryUnlockTimeoutSeconds
        protectedHistoryLockTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.lockProtectedHistory()
        }
    }

    private func reloadItemsForProtectionState() {
        items = historyRepository.load().items
        sortItems()
    }
}
