import AppKit
import SwiftUI

private struct InstalledApp: Identifiable {
    let id: String
    let name: String
    let icon: NSImage

    static func discover() -> [InstalledApp] {
        let fm = FileManager.default
        let searchDirs = [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications",
        ]
        var seen = Set<String>()
        var apps: [InstalledApp] = []

        for dir in searchDirs {
            guard let urls = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: dir),
                includingPropertiesForKeys: nil
            ) else { continue }

            for url in urls where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      !seen.contains(bundleID) else { continue }
                seen.insert(bundleID)
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                apps.append(InstalledApp(id: bundleID, name: name, icon: icon))
            }
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct IgnoredAppsEditor: View {
    @ObservedObject var settings: AppSettings
    @State private var installedApps: [InstalledApp] = []
    @State private var searchText = ""

    init(settings: AppSettings) {
        self.settings = settings
    }

    private var ignoredSet: Set<String> {
        settings.ignoredBundleIdentifierSet
    }

    private var filteredApps: [InstalledApp] {
        let ignored = installedApps.filter { ignoredSet.contains($0.id) }
        let available = installedApps.filter { !ignoredSet.contains($0.id) }

        if searchText.isEmpty {
            return ignored + available
        }
        return (ignored + available).filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ignore These Apps".localized)
                    .font(.headline)
                Spacer()
                Text("%d ignored".localized(ignoredSet.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps…".localized, text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Clear Search".localized)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredApps) { app in
                        AppToggleRow(
                            app: app,
                            isIgnored: ignoredSet.contains(app.id),
                            toggle: { toggleApp(app) }
                        )
                        if app.id != filteredApps.last?.id {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
            }
            .frame(height: 200)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))

            SettingsNote("Ignore rules only affect new copies and won't delete existing history.".localized)
        }
        .onAppear {
            if installedApps.isEmpty {
                installedApps = InstalledApp.discover()
            }
        }
    }

    private func toggleApp(_ app: InstalledApp) {
        var ids = ignoredSet
        if ids.contains(app.id) {
            ids.remove(app.id)
        } else {
            ids.insert(app.id)
        }
        settings.ignoredBundleIdentifiers = ids.sorted().joined(separator: "\n")
    }
}

private struct AppToggleRow: View {
    let app: InstalledApp
    let isIgnored: Bool
    let toggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Text(app.id)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isIgnored ? "eye.slash.fill" : "eye")
                    .font(.system(size: 13))
                    .foregroundStyle(isIgnored ? Color.orange : Color.secondary.opacity(0.4))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                isHovering ? Color.primary.opacity(0.04) : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.name)
        .accessibilityValue(isIgnored ? "Ignored".localized : "Recorded".localized)
        .accessibilityHint("Toggles whether clipboard content from this app is recorded.".localized)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.08)) {
                isHovering = hovering
            }
        }
    }
}
