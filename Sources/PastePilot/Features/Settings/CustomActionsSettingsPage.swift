import SwiftUI

struct CustomActionsSettingsPage: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsPane(id: SettingsTab.actions) {
            SettingsGroup(title: "Local Template Actions".localized) {
                if settings.customClipboardActions.isEmpty {
                    ContentUnavailableView(
                        "No Custom Actions".localized,
                        systemImage: "wand.and.stars",
                        description: Text(
                            "Create a local transform that copies its result to the clipboard.".localized
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 110)
                } else {
                    ForEach($settings.customClipboardActions) { $action in
                        CustomActionEditorRow(
                            action: $action,
                            delete: { delete(action.id) }
                        )
                        if action.id != settings.customClipboardActions.last?.id {
                            Divider()
                        }
                    }
                }

                Button {
                    addAction()
                } label: {
                    Label("Add Action".localized, systemImage: "plus")
                }
                .disabled(
                    settings.customClipboardActions.count
                        >= CustomClipboardAction.maximumCount
                )
            }

            SettingsGroup(title: "Template Reference".localized) {
                SettingsNote(
                    "Placeholders: {{content}}, {{title}}, {{kind}}, {{sourceApp}}, {{ocr}}, {{imageURL}}, {{imagePath}}, {{filePaths}}, and {{newline}}.".localized
                )
                SettingsNote(
                    "Transforms: |uppercase, |lowercase, |trim, |urlencode, and |jsonescape. Example: {{content|trim|uppercase}}".localized
                )
                Label(
                    "Custom actions only transform local data and never run shell commands, access the network, or write files.".localized,
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func addAction() {
        guard settings.customClipboardActions.count
                < CustomClipboardAction.maximumCount else {
            return
        }
        settings.customClipboardActions.append(CustomClipboardAction())
    }

    private func delete(_ id: UUID) {
        settings.customClipboardActions.removeAll { $0.id == id }
    }
}

private struct CustomActionEditorRow: View {
    @Binding var action: CustomClipboardAction
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Toggle("", isOn: $action.isEnabled)
                    .labelsHidden()
                    .accessibilityLabel("Enable Custom Action".localized)
                TextField("Action Name".localized, text: $action.title)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $action.scope) {
                    ForEach(CustomClipboardActionScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .labelsHidden()
                .frame(width: 125)
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete Custom Action".localized)
            }

            TextEditor(text: $action.template)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 64, maxHeight: 100)
                .padding(6)
                .background(
                    Color(nsColor: .textBackgroundColor).opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                )
                .accessibilityLabel("Action Template".localized)
        }
    }
}
