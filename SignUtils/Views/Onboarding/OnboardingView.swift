import SignKit
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var isAddingKey = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 14) {
                        IconBadge(symbol: "checkmark.seal.fill", color: .accentColor, size: 84)
                            .shadow(color: .accentColor.opacity(0.35), radius: 18, y: 8)
                        Text("SignUtils")
                            .font(.largeTitle.bold())
                        Text("Signing assets for sideloading, without the developer portal busywork.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 32)

                    VStack(alignment: .leading, spacing: 18) {
                        Feature(
                            symbol: "wand.and.stars", color: .blue, title: "One guided flow",
                            text: "Pick the signing type, App ID, capabilities, devices and certificate. SignUtils does the rest.")
                        Feature(
                            symbol: "doc.zipper", color: .purple, title: "Ready-to-import archives",
                            text: "Every bundle is a zip with the .p12, its password and the .mobileprovision.")
                        Feature(
                            symbol: "tray.full", color: .teal, title: "A library you can trust",
                            text: "Keep every bundle, see what expired or was revoked, and share it again anytime.")
                        Feature(
                            symbol: "xmark.seal", color: .red, title: "Clean up just as easily",
                            text: "Revoke certificates, delete profiles and App IDs, and manage devices.")
                    }
                    .frame(maxWidth: 520)

                    VStack(spacing: 12) {
                        Button {
                            isAddingKey = true
                        } label: {
                            Label("Add App Store Connect API Key", systemImage: "key.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("addKey")

                        Button {
                            Task { await model.enterDemo(seedLibrary: true) }
                        } label: {
                            Text("Explore the Demo")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityIdentifier("exploreDemo")

                        Text("Your key never leaves this device. It is stored in the Keychain and only used to talk to api.appstoreconnect.apple.com.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 420)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .sheet(isPresented: $isAddingKey) {
                AddAccountView()
                    .environment(model)
            }
        }
    }
}

private struct Feature: View {
    var symbol: String
    var color: Color
    var title: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(symbol: symbol, color: color, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct AddAccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: APICredentials.Kind = .team
    @State private var keyID = ""
    @State private var issuerID = ""
    @State private var privateKey = ""
    @State private var keyFileName: String?
    @State private var isImporting = false
    @State private var isVerifying = false
    @State private var errorMessage: String?

    private var draft: APICredentials {
        APICredentials(
            name: name.isEmpty ? "App Store Connect" : name, kind: kind, keyID: keyID, issuerID: issuerID,
            privateKeyPEM: privateKey)
    }

    private var canSave: Bool {
        keyID.count == 10 && !privateKey.isEmpty && (kind == .individual || !issuerID.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("My Team"))
                        .accessibilityIdentifier("accountName")
                    Picker("Key type", selection: $kind) {
                        Text("Team").tag(APICredentials.Kind.team)
                        Text("Individual").tag(APICredentials.Kind.individual)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Create a key with the Admin or App Manager role under Users and Access → Integrations → App Store Connect API.")
                }

                Section("Key") {
                    TextField("Key ID", text: $keyID, prompt: Text("2X9R4HXF34"))
                        .font(.body.monospaced())
                        .plainTextInput()
                        .accessibilityIdentifier("keyID")
                    if kind == .team {
                        TextField("Issuer ID", text: $issuerID, prompt: Text("57246542-96fe-1a63-e053-0824d011072a"))
                            .font(.body.monospaced())
                            .plainTextInput()
                            .accessibilityIdentifier("issuerID")
                    }
                }

                Section {
                    Button {
                        isImporting = true
                    } label: {
                        Label(keyFileName ?? "Choose AuthKey .p8 File…", systemImage: keyFileName == nil ? "doc.badge.plus" : "checkmark.circle.fill")
                    }
                    Button {
                        if let text = Clipboard.string {
                            privateKey = text
                            keyFileName = "Pasted key"
                        }
                    } label: {
                        Label("Paste Private Key", systemImage: "doc.on.clipboard")
                    }
                    if !privateKey.isEmpty {
                        Text(privateKey.prefix(64) + "…")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } header: {
                    Text("Private key")
                } footer: {
                    Text("Apple only lets you download the .p8 once. It stays in this device’s Keychain.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Link(destination: URL(string: "https://appstoreconnect.apple.com/access/integrations/api")!) {
                        Label("Open App Store Connect", systemImage: "arrow.up.right.square")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add API Key")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isVerifying {
                        ProgressView()
                    } else {
                        Button("Connect") { Task { await save() } }
                            .disabled(!canSave)
                            .accessibilityIdentifier("connect")
                    }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.p8Key, .data, .plainText]) { result in
                importKey(result)
            }
        }
        #if os(macOS)
            .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    private func importKey(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                privateKey = try String(contentsOf: url, encoding: .utf8)
                keyFileName = url.lastPathComponent
                if keyID.isEmpty, let detected = APICredentials.keyID(fromFileName: url.lastPathComponent) {
                    keyID = detected
                }
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        isVerifying = true
        defer { isVerifying = false }
        do {
            try await model.addAccount(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
