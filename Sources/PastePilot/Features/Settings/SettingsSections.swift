import AppKit
import SwiftUI

struct GeneralSettingsPage: View {
    @ObservedObject var settings: AppSettings
    let accessibilityGranted: Bool
    let requestPermission: () -> Void

    var body: some View {
        SettingsPane(id: SettingsTab.general) {
            SettingsGroup {
                Toggle("Launch PastePilot at Login".localized, isOn: $settings.launchAtLogin)
                Toggle("Monitor Clipboard".localized, isOn: $settings.monitoringEnabled)
                SettingsNote("When disabled, existing history can still be searched and copied.".localized)
            }

            SettingsGroup(title: "Global Shortcuts".localized) {
                SettingsRow(title: "Open PastePilot".localized) {
                    HotKeyRecorder(
                        keyCode: $settings.hotKeyCode,
                        modifiers: $settings.hotKeyModifiers
                    )
                    .frame(width: 190, height: 34)
                }
                SettingsRow(title: "Paste as Plain Text".localized) {
                    HotKeyRecorder(
                        keyCode: $settings.plainTextHotKeyCode,
                        modifiers: $settings.plainTextHotKeyModifiers,
                        defaultKeyCode: AppSettings.defaultPlainTextHotKeyCode,
                        defaultModifiers: AppSettings.defaultPlainTextHotKeyModifiers,
                        accessibilityLabel: "Paste as Plain Text Shortcut".localized
                    )
                    .frame(width: 190, height: 34)
                }
                SettingsNote("Click a shortcut field and press a new combination; press Delete to reset.".localized)
                if shortcutsConflict {
                    SettingsNote(
                        "Choose a different shortcut; both global actions currently use the same keys.".localized
                    )
                    .foregroundStyle(.red)
                } else if let warning = settings.hotKeyRegistrationWarning {
                    SettingsNote(warning)
                        .foregroundStyle(.orange)
                } else {
                    SettingsNote(
                        "Paste as Plain Text and Paste After Copying require Accessibility permission.".localized
                    )
                }
            }

            SettingsGroup {
                HStack {
                    Label(
                        accessibilityGranted
                            ? "Accessibility Permission Granted".localized
                            : "Accessibility Permission Required".localized,
                        systemImage: accessibilityGranted
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(accessibilityGranted ? .green : .orange)
                    Spacer()
                    if !accessibilityGranted {
                        Button("Open Accessibility Settings".localized) {
                            requestPermission()
                        }
                    }
                }

                if !accessibilityGranted {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Permission stopped working after an update?".localized)
                            .font(.caption.weight(.semibold))
                        Text("1. Select the old PastePilot in Accessibility settings, then click the minus button at the bottom.".localized)
                        Text("2. Close old DMGs, then add and enable /Applications/PastePilot.app again.".localized)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var shortcutsConflict: Bool {
        settings.hotKeyCode == settings.plainTextHotKeyCode
            && settings.hotKeyModifiers == settings.plainTextHotKeyModifiers
    }
}

struct StorageSettingsPage: View {
    @ObservedObject var settings: AppSettings
    let storageByteCount: Int64
    let rerunOCR: () -> Void
    let rerunBarcodeDetection: () -> Void

    var body: some View {
        SettingsPane(id: SettingsTab.storage) {
            SettingsGroup {
                SettingsRow(title: "Keep up to".localized) {
                    Picker("", selection: $settings.historyLimit) {
                        ForEach(AppSettings.supportedHistoryLimits, id: \.self) { limit in
                            Text(historyLimitLabel(limit)).tag(limit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                SettingsRow(title: "Auto-delete After".localized) {
                    Picker("", selection: $settings.historyTimeoutSeconds) {
                        ForEach(AppSettings.supportedHistoryTimeoutsSeconds, id: \.self) { timeout in
                            Text(historyTimeoutLabel(timeout)).tag(timeout)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                SettingsRow(title: "Storage Limit".localized) {
                    Picker("", selection: $settings.storageLimitMB) {
                        ForEach(AppSettings.supportedStorageLimitsMB, id: \.self) { limit in
                            Text(storageLimitLabel(limit)).tag(limit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                SettingsRow(title: "Current Usage".localized) {
                    Text(byteCountLabel(storageByteCount))
                        .foregroundStyle(.secondary)
                }
                SettingsNote("Pinned items are excluded from this limit and never auto-deleted.".localized)
            }

            SettingsGroup {
                SettingsRow(title: "Image Size Limit".localized) {
                    Picker("", selection: $settings.imageSizeLimitMB) {
                        ForEach(AppSettings.supportedImageSizeLimitsMB, id: \.self) { limit in
                            Text(imageSizeLimitLabel(limit)).tag(limit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                Toggle(
                    "Deduplicate Similar Images".localized,
                    isOn: $settings.perceptualImageDeduplicationEnabled
                )
                SettingsNote(
                    "Use a local perceptual hash to merge visually identical images saved with different encodings.".localized
                )
            }

            SettingsGroup(title: "Link Metadata".localized) {
                Toggle(
                    "Fetch Link Titles".localized,
                    isOn: $settings.linkMetadataFetchingEnabled
                )
                SettingsNote(
                    "When enabled, copied web links are requested from their destination to fetch a title and description. This may reveal the link to that website.".localized
                )
            }

            SettingsGroup(title: "Sensitive Content".localized) {
                SettingsRow(title: "When Detected".localized) {
                    Picker("", selection: $settings.sensitiveContentStoragePolicy) {
                        ForEach(
                            SensitiveContentStoragePolicy.allCases,
                            id: \.rawValue
                        ) { policy in
                            Text(policy.title).tag(policy.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                SettingsRow(title: "Custom Patterns".localized) {
                    TextEditor(text: $settings.customSensitivePatterns)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(width: 260, height: 86)
                        .background(
                            Color(nsColor: .textBackgroundColor).opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.quaternary, lineWidth: 0.5)
                        )
                        .accessibilityLabel("Custom Sensitive Patterns".localized)
                }
                SettingsNote("Use one literal match per line. Prefix regular expressions with regex:. Invalid regular expressions are ignored.".localized)
                SettingsNote("Redacted or skipped sensitive clipboard content is not recoverable from history.".localized)
            }

            SettingsGroup(title: "Image Text Recognition".localized) {
                SettingsRow(title: "OCR Mode".localized) {
                    Picker("", selection: $settings.ocrRecognitionMode) {
                        ForEach(OCRRecognitionMode.allCases, id: \.rawValue) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                SettingsRow(title: "OCR Languages".localized) {
                    Picker("", selection: $settings.ocrLanguageMode) {
                        ForEach(OCRLanguageMode.allCases, id: \.rawValue) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                SettingsRow(title: "Existing Images".localized) {
                    HStack {
                        Button("Re-run OCR".localized, action: rerunOCR)
                            .disabled(
                                OCRRecognitionMode(rawValue: settings.ocrRecognitionMode)
                                    == .off
                            )
                        Button("Scan Barcodes".localized, action: rerunBarcodeDetection)
                    }
                }
                SettingsNote("OCR and barcode detection run locally on copied images and make their contents searchable.".localized)
            }
        }
    }

    private func historyLimitLabel(_ limit: Int) -> String {
        "%d items".localized(limit)
    }

    private func historyTimeoutLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0:
            "Never".localized
        case 3_600:
            "1 hour".localized
        case 86_400:
            "24 hours".localized
        case 604_800:
            "7 days".localized
        case 2_592_000:
            "30 days".localized
        default:
            "\(seconds) s"
        }
    }

    private func imageSizeLimitLabel(_ limit: Int) -> String {
        "\(limit) MB"
    }

    private func storageLimitLabel(_ limit: Int) -> String {
        guard limit > 0 else { return "No Limit".localized }
        if limit >= 1_024 {
            return "1 GB"
        }
        return "\(limit) MB"
    }

    private func byteCountLabel(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: byteCount,
            countStyle: .file
        )
    }
}

struct AppearanceSettingsPage: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsPane(id: SettingsTab.appearance) {
            SettingsGroup {
                SettingsRow(title: "Menu Bar Icon".localized) {
                    Picker("", selection: $settings.menuBarIconStyle) {
                        ForEach(MenuBarIconStyle.allCases, id: \.rawValue) { style in
                            Label {
                                Text(style.displayName)
                            } icon: {
                                Image(nsImage: style.previewImage)
                                    .renderingMode(.template)
                            }
                                .tag(style.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                SettingsRow(title: "Theme".localized) {
                    Picker("", selection: $settings.appearanceMode) {
                        ForEach(AppAppearanceMode.allCases, id: \.rawValue) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                SettingsNote("Choose whether PastePilot follows the system appearance or uses a fixed light or dark theme.".localized)
            }

            SettingsGroup {
                Toggle("Show Details on Hover".localized, isOn: $settings.hoverPreviewEnabled)
                SettingsNote("Hover briefly to see full content, source app, and metadata.".localized)
                Toggle("Animate Preview".localized, isOn: $settings.previewAnimationEnabled)
                SettingsNote("Fade the detail preview in and out. Switching apps always closes it instantly.".localized)
            }

            SettingsGroup {
                Toggle(
                    "Paste After Copying".localized,
                    isOn: $settings.pasteAfterCopying
                )
                SettingsNote("After a successful copy, close the panel and press Command-V in the previous app.".localized)
                SettingsRow(title: "After Copying".localized) {
                    Picker("", selection: $settings.pasteCloseBehavior) {
                        Text("Keep Panel Open".localized)
                            .tag(PasteCloseBehavior.keepOpen.rawValue)
                        Text("Close Preview".localized)
                            .tag(PasteCloseBehavior.closePreview.rawValue)
                        Text("Close Panel".localized)
                            .tag(PasteCloseBehavior.closePanel.rawValue)
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .disabled(settings.pasteAfterCopying)
                }
                SettingsNote("Choose what closes after you copy or transform an item.".localized)
            }

            SettingsGroup {
                SettingsRow(title: "Menu Bar Window".localized) {
                    Text("Adaptive".localized)
                        .foregroundStyle(.secondary)
                }
                SettingsNote("The window grows with your results and uses the selected theme.".localized)
            }
        }
    }
}

struct IgnoredAppsSettingsPage: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsPane(id: SettingsTab.ignored) {
            SettingsGroup {
                IgnoredAppsEditor(settings: settings)
            }

            SettingsGroup {
                Label(
                    "Ignore rules only affect new copies and won't delete existing history.".localized,
                    systemImage: "info.circle"
                )
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct AdvancedSettingsPage: View {
    let openDataFolder: () -> Void
    let exportBackup: () -> Void
    let restoreBackup: () -> Void
    let showClearHistoryConfirmation: () -> Void
    let updateController: UpdateController
    let showResetConfirmation: () -> Void

    var body: some View {
        SettingsPane(id: SettingsTab.advanced) {
            SettingsGroup {
                SettingsRow(title: "Local Data".localized) {
                    Button("Open Data Folder".localized, action: openDataFolder)
                }
                SettingsRow(title: "Backup".localized) {
                    Button("Export Backup…".localized, action: exportBackup)
                }
                SettingsRow(title: "Restore".localized) {
                    Button("Restore Backup…".localized, role: .destructive) {
                        restoreBackup()
                    }
                }
                SettingsNote("Backups include history, images, and externalized text. Restoring creates a pre-restore backup first.".localized)
                SettingsRow(title: "History".localized) {
                    Button("Clear Unpinned".localized, role: .destructive) {
                        showClearHistoryConfirmation()
                    }
                }
            }

            SettingsGroup {
                SettingsRow(title: "Updates".localized) {
                    Button("Check for Updates…".localized) {
                        updateController.checkForUpdates()
                    }
                    .disabled(!updateController.canCheckForUpdates)
                }
                Toggle(
                    "Automatically Check for Updates".localized,
                    isOn: Binding(
                        get: { updateController.automaticallyChecksForUpdates },
                        set: { updateController.automaticallyChecksForUpdates = $0 }
                    )
                )
            }

            SettingsGroup {
                SettingsRow(title: "Preferences".localized) {
                    Button("Reset to Defaults…".localized) {
                        showResetConfirmation()
                    }
                }
                SettingsNote("Resetting preferences won't delete clipboard history or images.".localized)
            }
        }
    }
}
