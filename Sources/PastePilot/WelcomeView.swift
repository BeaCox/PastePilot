import AppKit
import SwiftUI

struct WelcomeView: View {
    let shortcut: String
    let plainTextShortcut: String
    let dismiss: () -> Void
    @State private var accessibilityGranted = EventPostingPermission.isGranted
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: AppIconRenderer.icon(size: 256))
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("Welcome to PastePilot".localized)
                    .font(.title2.bold())
                Text("Smart Clipboard for Developers".localized)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                statusRow(
                    granted: accessibilityGranted,
                    symbol: "hand.raised",
                    title: "Global Shortcuts".localized,
                    detail: accessibilityGranted
                        ? "Both shortcuts are ready.".localized
                        : "Open PastePilot works now; paste as plain text needs Accessibility permission.".localized
                )
                Divider().padding(.leading, 42)
                statusRow(
                    granted: true,
                    symbol: "clipboard",
                    title: "Clipboard Monitoring".localized,
                    detail: "Active — no additional permission needed.".localized
                )
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            if !accessibilityGranted {
                Button("Request Permission".localized) {
                    accessibilityGranted = EventPostingPermission.request()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            VStack(spacing: 6) {
                Text("Press %@ to open PastePilot anytime.".localized(shortcut))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    "Press %@ to paste without formatting.".localized(
                        plainTextShortcut
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button(accessibilityGranted ? "Get Started".localized : "Skip for Now".localized) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(32)
        .frame(width: 480, height: 420)
        .onAppear {
            guard !accessibilityGranted else { return }
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in
                    let trusted = EventPostingPermission.isGranted
                    if trusted != accessibilityGranted {
                        withAnimation { accessibilityGranted = trusted }
                        if trusted { pollTimer?.invalidate() }
                    }
                }
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
        }
    }

    private func statusRow(granted: Bool, symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .font(.system(size: 18))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
