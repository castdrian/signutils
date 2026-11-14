import SignKit
import SwiftUI

struct LibraryDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var entry: LibraryEntry
    @State private var revealPassword = false
    @State private var confirmation: Confirmation?
    @State private var isWorking = false
    @State private var exportedFile: ExportedFile?

    enum Confirmation: Identifiable {
        case revokeAll
        case deleteProfile
        case remove
        var id: Self { self }
    }

    private var bundle: SigningBundle { entry.bundle }
    private var status: LibraryEntry.Status { entry.effectiveStatus() }
    private var certificateIsLive: Bool { model.certificates.contains { $0.id == bundle.certificateID } }
    private var profileIsLive: Bool { model.profiles.contains { $0.id == bundle.profileID } }
    private var sharingProfiles: Int { model.entries(forCertificate: bundle.certificateID).count - 1 }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        IconBadge(symbol: "doc.zipper", color: status == .active ? .accentColor : .gray, size: 56)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(bundle.name).font(.title2.bold())
                            HStack {
                                KindPill(kind: bundle.kind)
                                StatusPill(status: status)
                            }
                        }
                    }
                    if let url = model.archiveURL(for: entry) {
                        ShareLink(item: url) {
                            Label("Share Archive", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("shareArchive")
                    }
                }
                .padding(.vertical, 6)
            }

            Section("P12 Password") {
                HStack {
                    Text(revealPassword ? bundle.password : String(repeating: "•", count: 12))
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        revealPassword.toggle()
                    } label: {
                        Image(systemName: revealPassword ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(revealPassword ? "Hide password" : "Show password")
                    Button {
                        Clipboard.copy(bundle.password)
                        model.toast = Toast("Password copied", symbol: "doc.on.doc.fill")
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy password")
                }
            }

            Section("App ID") {
                LabeledValue(label: "Identifier", value: bundle.bundleIdentifier, monospaced: true, copyable: true)
                LabeledValue(label: "Team", value: "\(bundle.teamName) (\(bundle.teamID))")
                if !bundle.capabilities.isEmpty {
                    CapabilityFlow(capabilities: bundle.capabilities)
                }
            }

            Section("Certificate") {
                LabeledValue(label: "Type", value: bundle.certificateType.displayName)
                LabeledValue(label: "Name", value: bundle.certificateName)
                LabeledValue(label: "Serial", value: bundle.certificateSerial, monospaced: true)
                LabeledContent("Status") {
                    if certificateIsLive {
                        ExpiryText(date: bundle.certificateExpiration)
                    } else {
                        Text("Revoked").foregroundStyle(.red)
                    }
                }
            }

            Section("Provisioning Profile") {
                LabeledValue(label: "Name", value: bundle.profileName)
                LabeledValue(label: "Type", value: bundle.profileType.displayName)
                LabeledValue(label: "UUID", value: bundle.profileUUID, monospaced: true, copyable: true)
                LabeledContent("Status") {
                    if profileIsLive {
                        ExpiryText(date: bundle.profileExpiration)
                    } else {
                        Text("Deleted").foregroundStyle(.red)
                    }
                }
            }

            if !bundle.devices.isEmpty {
                Section("Devices (\(bundle.devices.count))") {
                    ForEach(bundle.devices, id: \.udid) { device in
                        HStack(spacing: 12) {
                            Image(systemName: device.deviceClass.symbolName)
                                .foregroundStyle(device.deviceClass.tint)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(device.name)
                                Text(device.udid).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Archive Contents") {
                ForEach(model.contents(of: entry), id: \.path) { file in
                    LabeledContent {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file))
                            .foregroundStyle(.secondary)
                    } label: {
                        Label((file.path as NSString).lastPathComponent, systemImage: symbol(for: file.path))
                    }
                }
            }

            Section {
                if profileIsLive {
                    Button(role: .destructive) {
                        confirmation = .deleteProfile
                    } label: {
                        Label("Delete Provisioning Profile", systemImage: "doc.badge.ellipsis")
                    }
                }
                if certificateIsLive || profileIsLive {
                    Button(role: .destructive) {
                        confirmation = .revokeAll
                    } label: {
                        Label("Revoke Certificate and Profile", systemImage: "xmark.seal")
                    }
                    .accessibilityIdentifier("revokeAll")
                }
                Button(role: .destructive) {
                    confirmation = .remove
                } label: {
                    Label("Remove from Library", systemImage: "trash")
                }
            } footer: {
                Text("Revoking a certificate invalidates every app signed with it and every profile that uses it.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(bundle.name)
        .inlineTitle()
        .disabled(isWorking)
        .overlay { if isWorking { ProgressView().controlSize(.large) } }
        .confirmationDialog(title, isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible, presenting: confirmation) { kind in
            switch kind {
            case .revokeAll:
                Button("Revoke", role: .destructive) { run { await model.revoke(entry, certificate: true, profile: true) } }
            case .deleteProfile:
                Button("Delete Profile", role: .destructive) { run { await model.revoke(entry, certificate: false, profile: true) } }
            case .remove:
                Button("Remove", role: .destructive) {
                    model.removeFromLibrary(entry)
                    dismiss()
                }
            }
        } message: { kind in
            switch kind {
            case .revokeAll:
                Text(sharingProfiles > 0
                    ? "This certificate is also used by \(sharingProfiles) other bundle(s) in your library. They will stop working too."
                    : "Apps signed with this certificate will stop launching once iOS checks its status.")
            case .deleteProfile:
                Text("The certificate stays valid. Apps that embed this profile stop launching.")
            case .remove:
                Text("Only the local archive is deleted. Nothing changes in App Store Connect.")
            }
        }
    }

    private var title: String {
        switch confirmation {
        case .revokeAll: "Revoke \(bundle.certificateType.displayName) certificate?"
        case .deleteProfile: "Delete \(bundle.profileName)?"
        case .remove: "Remove \(bundle.name) from the library?"
        case nil: ""
        }
    }

    private func run(_ operation: @escaping () async -> Void) {
        Task {
            isWorking = true
            await operation()
            isWorking = false
        }
    }

    private func symbol(for path: String) -> String {
        switch (path as NSString).pathExtension {
        case "p12": "key.fill"
        case "mobileprovision": "doc.badge.gearshape"
        case "cer": "checkmark.seal"
        case "json": "curlybraces"
        default: "doc.text"
        }
    }
}

struct CapabilityFlow: View {
    var capabilities: [CapabilityType]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(capabilities) { capability in
                Pill(text: capability.displayName, color: .accentColor, symbol: capability.symbolName)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let addition = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += addition
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
