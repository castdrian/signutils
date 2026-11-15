import SignKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @State private var isAddingKey = false
    @State private var pendingRemoval: APICredentials?

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if model.isDemo {
                        HStack {
                            Label(DemoAppStoreConnect.teamName, systemImage: "sparkles")
                            Spacer()
                            Text("Demo").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(model.accounts) { account in
                        Button {
                            Task { await model.activate(account) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name).foregroundStyle(.primary)
                                    Text("\(account.kind == .team ? "Team" : "Individual") key \(account.keyID)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !model.isDemo, model.activeKeyID == account.keyID {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Remove", role: .destructive) { pendingRemoval = account }
                        }
                        .contextMenu {
                            Button(role: .destructive) { pendingRemoval = account } label: { Label("Remove Key", systemImage: "trash") }
                        }
                    }
                    Button {
                        isAddingKey = true
                    } label: {
                        Label("Add API Key", systemImage: "plus")
                    }
                } header: {
                    Text("Accounts")
                } footer: {
                    Text("Keys are stored in the Keychain on this device only.")
                }

                Section("Status") {
                    LabeledContent("Certificates", value: "\(model.certificates.count)")
                    LabeledContent("Profiles", value: "\(model.profiles.count)")
                    LabeledContent("App IDs", value: "\(model.bundleIDs.count)")
                    LabeledContent("Devices", value: "\(model.devices.filter { $0.status == .enabled }.count) enabled")
                    LabeledContent("Library", value: "\(model.entries.count) bundles")
                    if case .loaded(let date) = model.loadState {
                        LabeledContent("Updated") { Text(date, format: .relative(presentation: .named)) }
                    }
                }

                Section {
                    if model.isDemo {
                        Button("Exit Demo") { Task { await model.leaveDemo() } }
                    } else {
                        Button("Explore the Demo") { Task { await model.enterDemo(seedLibrary: true) } }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: version)
                    Link(destination: URL(string: "https://github.com/castdrian/signutils")!) {
                        Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: URL(string: "https://github.com/castdrian/signutils/issues")!) {
                        Label("Report an Issue", systemImage: "ladybug")
                    }
                    Link(destination: URL(string: "https://github.com/sponsors/castdrian")!) {
                        Label("Sponsor", systemImage: "heart")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                if isPresented {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $isAddingKey) { AddAccountView().environment(model) }
            .confirmationDialog(
                "Remove this key?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                titleVisibility: .visible, presenting: pendingRemoval
            ) { account in
                Button("Remove \(account.name)", role: .destructive) { Task { await model.removeAccount(account) } }
            } message: { _ in
                Text("The key is removed from this device. It stays active in App Store Connect until you revoke it there. Library bundles made with it are kept.")
            }
        }
    }
}
