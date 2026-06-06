import AppKit
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case storage
    case appearance
    case ignored
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .storage: "存储"
        case .appearance: "外观"
        case .ignored: "忽略"
        case .advanced: "高级"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .storage: "internaldrive"
        case .appearance: "paintpalette"
        case .ignored: "nosign"
        case .advanced: "gearshape.2"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let openDataFolder: () -> Void
    let clearUnpinnedHistory: () -> Void
    @State private var selectedTab: SettingsTab = .general
    @State private var showsResetConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            ScrollView {
                page
                    .padding(.horizontal, 38)
                    .padding(.vertical, 30)
            }
        }
        .frame(width: 700, height: 570)
        .confirmationDialog(
            "恢复默认设置？",
            isPresented: $showsResetConfirmation
        ) {
            Button("恢复默认设置", role: .destructive) {
                settings.reset()
            }
        } message: {
            Text("剪贴板历史不会被删除。")
        }
    }

    private var tabBar: some View {
        HStack(spacing: 14) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 29, weight: .regular))
                            .frame(height: 32)
                        Text(tab.title)
                            .font(.callout)
                    }
                    .foregroundStyle(
                        selectedTab == tab ? Color.accentColor : Color.secondary
                    )
                    .frame(width: 78, height: 76)
                    .background(
                        selectedTab == tab
                            ? Color.primary.opacity(0.06)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.08))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var page: some View {
        switch selectedTab {
        case .general:
            generalPage
        case .storage:
            storagePage
        case .appearance:
            appearancePage
        case .ignored:
            ignoredPage
        case .advanced:
            advancedPage
        }
    }

    private var generalPage: some View {
        SettingsPage(title: "通用") {
            SettingsSection {
                Toggle("登录时启动 PastePilot", isOn: $settings.launchAtLogin)
                Toggle("监听剪贴板", isOn: $settings.monitoringEnabled)
                SettingsNote("关闭监听后，已有历史仍可搜索和复制。")
            }

            SettingsSection {
                SettingsRow(title: "打开 PastePilot") {
                    HotKeyRecorder(
                        keyCode: $settings.hotKeyCode,
                        modifiers: $settings.hotKeyModifiers
                    )
                }
                SettingsNote("点击快捷键框后录制新组合；按 Delete 恢复默认值。")
            }
        }
    }

    private var storagePage: some View {
        SettingsPage(title: "存储") {
            SettingsSection {
                SettingsRow(title: "最多保留") {
                    Picker("", selection: $settings.historyLimit) {
                        Text("50 条").tag(50)
                        Text("100 条").tag(100)
                        Text("200 条").tag(200)
                        Text("500 条").tag(500)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                SettingsNote("固定项目不计入这个数量，也不会被自动清理。")
            }

            SettingsSection {
                SettingsRow(title: "单张图片上限") {
                    Picker("", selection: $settings.imageSizeLimitMB) {
                        Text("5 MB").tag(5)
                        Text("10 MB").tag(10)
                        Text("25 MB").tag(25)
                        Text("50 MB").tag(50)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                SettingsRow(title: "数据目录") {
                    Button("在 Finder 中显示", action: openDataFolder)
                }
            }
        }
    }

    private var appearancePage: some View {
        SettingsPage(title: "外观") {
            SettingsSection {
                Toggle("悬停显示完整详情", isOn: $settings.hoverPreviewEnabled)
                SettingsNote("鼠标停留约半秒后显示完整内容、来源应用和元数据。")
            }

            SettingsSection {
                SettingsRow(title: "菜单栏窗口") {
                    Text("400 × 450")
                        .foregroundStyle(.secondary)
                }
                SettingsNote("窗口保持紧凑，并自动跟随系统浅色或深色外观。")
            }
        }
    }

    private var ignoredPage: some View {
        SettingsPage(title: "忽略") {
            SettingsSection {
                Text("不记录以下应用")
                    .font(.headline)
                TextEditor(text: $settings.ignoredBundleIdentifiers)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .padding(6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                SettingsNote("每行填写一个 Bundle ID，例如 com.apple.keychainaccess。")
            }

            SettingsSection {
                Label("忽略规则只影响新复制内容，不会删除已有历史。", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var advancedPage: some View {
        SettingsPage(title: "高级") {
            SettingsSection {
                SettingsRow(title: "本地数据") {
                    Button("打开数据目录", action: openDataFolder)
                }
                SettingsRow(title: "历史记录") {
                    Button("清除未固定记录", role: .destructive, action: clearUnpinnedHistory)
                }
            }

            SettingsSection {
                SettingsRow(title: "偏好设置") {
                    Button("恢复默认设置…") {
                        showsResetConfirmation = true
                    }
                }
                SettingsNote("恢复设置不会删除剪贴板历史或图片文件。")
            }
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            content
        }
    }
}

private struct SettingsSection<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            content
        }
        .frame(minHeight: 28)
    }
}

private struct SettingsNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct AboutView: View {
    @ObservedObject var settings: AppSettings
    let version: String
    let openDataFolder: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "clipboard.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 84, height: 84)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))

            VStack(spacing: 5) {
                Text("PastePilot")
                    .font(.title.bold())
                Text("开发者的智能剪贴板")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("版本 \(version)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text("理解 JSON、代码、终端命令、报错、链接和图片，并提供下一步操作。所有数据仅保存在本机。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            HStack(spacing: 18) {
                Label(
                    "\(HotKeyFormatter.display(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)) 呼出",
                    systemImage: "keyboard"
                )
                Label("本地存储", systemImage: "lock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("打开数据文件夹", action: openDataFolder)
        }
        .padding(32)
        .frame(width: 460, height: 390)
    }
}
