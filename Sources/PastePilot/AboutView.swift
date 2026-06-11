import AppKit
import SwiftUI

struct AboutView: View {
    @ObservedObject var settings: AppSettings
    let version: String
    let openDataFolder: () -> Void
    let checkForUpdates: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 18) {
                Image(nsImage: AppIconRenderer.icon(size: 256))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .shadow(color: Color.accentColor.opacity(0.22), radius: 14, y: 7)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("PastePilot")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Smart Clipboard for Developers".localized)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Version %@".localized(version))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }

                Spacer()
            }
            .padding(.bottom, 20)

            Text("Understands developer text, rich text, images, and files — suggests the next action. All data stays on your Mac.".localized)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            HStack(spacing: 10) {
                AboutFeature(
                    symbol: "keyboard",
                    title: "Quick Access".localized,
                    detail: HotKeyFormatter.display(
                        keyCode: settings.hotKeyCode,
                        modifiers: settings.hotKeyModifiers
                    )
                )
                AboutFeature(
                    symbol: "lock.shield",
                    title: "Private by Design".localized,
                    detail: "Local Storage".localized
                )
                AboutFeature(
                    symbol: "wand.and.stars",
                    title: "Developer Actions".localized,
                    detail: "Built In".localized
                )
            }
            .padding(.bottom, 18)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Designed & Built by".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("BeaCox")
                        .font(.headline.weight(.semibold))
                }

                Spacer()

                Button(action: openDataFolder) {
                    Label("Data Folder".localized, systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: checkForUpdates) {
                    Label("Check for Updates…".localized, systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, 16)
        }
        .padding(30)
        .frame(width: 520, height: 390)
    }
}

private struct AboutFeature: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}
