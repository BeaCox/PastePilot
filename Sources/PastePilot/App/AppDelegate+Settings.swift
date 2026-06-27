import Combine
import Foundation
import ServiceManagement

extension AppDelegate {
    func configureSettingsObservers() {
        settings.$monitoringEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                if enabled {
                    self?.store.startMonitoring()
                    self?.store.captureCurrentClipboard()
                } else {
                    self?.store.stopMonitoring()
                }
            }
            .store(in: &cancellables)

        settings.$historyLimit
            .dropFirst()
            .sink { [weak self] limit in
                self?.store.applyHistoryLimit(limit)
            }
            .store(in: &cancellables)

        settings.$storageLimitMB
            .dropFirst()
            .sink { [weak self] _ in
                self?.store.applyStorageLimit()
            }
            .store(in: &cancellables)

        settings.$launchAtLogin
            .dropFirst()
            .sink { [weak self] enabled in
                self?.updateLoginItem(enabled: enabled)
            }
            .store(in: &cancellables)

        settings.$hotKeyCode
            .combineLatest(settings.$hotKeyModifiers)
            .dropFirst()
            .sink { [weak self] _, _ in
                self?.registerConfiguredHotKeys()
            }
            .store(in: &cancellables)

        settings.$plainTextHotKeyCode
            .combineLatest(settings.$plainTextHotKeyModifiers)
            .dropFirst()
            .sink { [weak self] _, _ in
                self?.registerConfiguredHotKeys()
            }
            .store(in: &cancellables)

        settings.$historyTimeoutSeconds
            .dropFirst()
            .sink { [weak self] _ in
                self?.store.purgeExpired()
            }
            .store(in: &cancellables)

        settings.$ocrRecognitionMode
            .dropFirst()
            .sink { [weak self] mode in
                if OCRRecognitionMode(rawValue: mode) == .off {
                    self?.store.cancelAllOCRTasks()
                }
            }
            .store(in: &cancellables)
    }

    func updateLoginItem(enabled: Bool) {
        guard !isSynchronizingLoginItem else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("PastePilot failed to update login item: \(error)")
            isSynchronizingLoginItem = true
            settings.launchAtLogin = SMAppService.mainApp.status == .enabled
            isSynchronizingLoginItem = false
        }
    }
}
