import SignKit
import SwiftUI

struct CertificatesView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingRevoke: Certificate?

    private var groups: [(CertificateType, [Certificate])] {
        Dictionary(grouping: model.certificates, by: \.certificateType)
            .map { ($0.key, $0.value) }
            .sorted { $0.0.displayName < $1.0.displayName }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.0) { type, certificates in
                    Section {
                        ForEach(certificates) { certificate in
                            CertificateRow(certificate: certificate, hasKey: model.keyedCertificateIDs.contains(certificate.id), usage: model.entries(forCertificate: certificate.id).count)
                                .swipeActions {
                                    Button("Revoke", role: .destructive) { pendingRevoke = certificate }
                                }
                                .contextMenu {
                                    Button(role: .destructive) { pendingRevoke = certificate } label: {
                                        Label("Revoke", systemImage: "xmark.seal")
                                    }
                                    Button { Clipboard.copy(certificate.serialNumber) } label: {
                                        Label("Copy Serial Number", systemImage: "doc.on.doc")
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text(type.displayName)
                            Spacer()
                            Text("\(certificates.count)")
                        }
                    }
                }
            }
            .overlay {
                LoadingOverlay(isEmpty: model.certificates.isEmpty)
                if model.certificates.isEmpty, case .loaded = model.loadState {
                    ContentUnavailableView("No certificates", systemImage: "checkmark.seal", description: Text("Certificates you create appear here."))
                }
            }
            .adaptiveListStyle()
            .navigationTitle("Certificates")
            .refreshable { await model.refresh() }
            .toolbar { ToolbarItem(placement: .primaryAction) { RefreshButton() } }
            .confirmationDialog(
                "Revoke this certificate?", isPresented: Binding(get: { pendingRevoke != nil }, set: { if !$0 { pendingRevoke = nil } }),
                titleVisibility: .visible, presenting: pendingRevoke
            ) { certificate in
                Button("Revoke \(certificate.certificateType.displayName)", role: .destructive) {
                    Task { await model.revokeCertificate(certificate) }
                }
            } message: { certificate in
                let usage = model.entries(forCertificate: certificate.id).count
                Text("\(certificate.name)\n\nApps signed with it stop launching and its profiles become invalid. \(usage > 0 ? "\(usage) bundle(s) in your library use it." : "") This cannot be undone.")
            }
        }
    }
}

private struct CertificateRow: View {
    var certificate: Certificate
    var hasKey: Bool
    var usage: Int

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: "checkmark.seal.fill", color: certificate.certificateType.tint, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(certificate.name).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 8) {
                    ExpiryText(date: certificate.expirationDate)
                    if hasKey {
                        Pill(text: "Key on device", color: .green, symbol: "key.fill")
                    }
                    if usage > 0 {
                        Pill(text: "\(usage) in library", color: .accentColor, symbol: "tray.full")
                    }
                }
                .font(.caption)
                Text(certificate.serialNumber)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ProfilesView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingDelete: Profile?
    @State private var search = ""
    @State private var exporting: DataDocument?
    @State private var exportName = ""

    private var visible: [Profile] {
        guard !search.isEmpty else { return model.profiles }
        return model.profiles.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(visible) { profile in
                ProfileRow(profile: profile, bundleID: model.bundleID(id: profile.bundleIDResource))
                    .swipeActions {
                        Button("Delete", role: .destructive) { pendingDelete = profile }
                    }
                    .contextMenu {
                        Button {
                            Task {
                                if let data = await model.profileContent(profile) {
                                    exportName = "\(SigningBundle.slug(profile.name)).mobileprovision"
                                    exporting = DataDocument(data: data)
                                }
                            }
                        } label: {
                            Label("Save Profile…", systemImage: "square.and.arrow.down")
                        }
                        Button(role: .destructive) { pendingDelete = profile } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .overlay {
                LoadingOverlay(isEmpty: model.profiles.isEmpty)
                if model.profiles.isEmpty, case .loaded = model.loadState {
                    ContentUnavailableView("No profiles", systemImage: "doc.badge.gearshape", description: Text("Provisioning profiles you create appear here."))
                }
            }
            .adaptiveListStyle()
            .navigationTitle("Profiles")
            .searchable(text: $search)
            .refreshable { await model.refresh() }
            .toolbar { ToolbarItem(placement: .primaryAction) { RefreshButton() } }
            .fileExporter(
                isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }), document: exporting,
                contentType: .mobileProvision, defaultFilename: exportName
            ) { _ in exporting = nil }
            .confirmationDialog(
                "Delete this profile?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible, presenting: pendingDelete
            ) { profile in
                Button("Delete \(profile.name)", role: .destructive) { Task { await model.deleteProfile(profile) } }
            } message: { _ in
                Text("Apps that embed this profile stop launching. The certificate and App ID are not affected.")
            }
        }
    }
}

private struct ProfileRow: View {
    var profile: Profile
    var bundleID: BundleID?

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: "doc.badge.gearshape.fill", color: profile.state == .active ? .teal : .gray, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(profile.name).font(.body.weight(.medium)).lineLimit(1)
                    if profile.state == .invalid {
                        Pill(text: "Invalid", color: .orange)
                    }
                }
                Text(bundleID?.identifier ?? profile.profileType.displayName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Text(profile.profileType.displayName)
                    if profile.profileType.includesDevices {
                        Label("\(profile.deviceIDs.count)", systemImage: "iphone")
                    }
                    ExpiryText(date: profile.expirationDate)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .fixedSize(horizontal: false, vertical: true)
    }
}
