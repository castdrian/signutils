import SignKit
import SwiftUI

struct AppIDsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var isAdding = false

    private var visible: [BundleID] {
        guard !search.isEmpty else { return model.bundleIDs }
        return model.bundleIDs.filter {
            $0.identifier.localizedCaseInsensitiveContains(search) || $0.name.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List(visible) { bundleID in
                NavigationLink(value: bundleID) {
                    HStack(spacing: 12) {
                        IconBadge(symbol: bundleID.isWildcard ? "asterisk" : "app.badge.fill", color: bundleID.isWildcard ? .orange : .indigo, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bundleID.name).lineLimit(1)
                            Text(bundleID.identifier).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(bundleID.platform.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .overlay { LoadingOverlay(isEmpty: model.bundleIDs.isEmpty) }
            .adaptiveListStyle()
            .navigationTitle("App IDs")
            .navigationDestination(for: BundleID.self) { AppIDDetailView(bundleID: $0) }
            .searchable(text: $search, prompt: "Search \(model.bundleIDs.count) App IDs")
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isAdding = true } label: { Label("Register App ID", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $isAdding) {
                AddAppIDView().environment(model)
            }
        }
    }
}

struct AppIDDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var bundleID: BundleID
    @State private var capabilities: [BundleIDCapability] = []
    @State private var isLoading = true
    @State private var busy: CapabilityType?
    @State private var confirmDelete = false

    private var profiles: [Profile] { model.profiles.filter { $0.bundleIDResource == bundleID.id } }

    var body: some View {
        Form {
            Section {
                LabeledValue(label: "Identifier", value: bundleID.identifier, monospaced: true, copyable: true)
                LabeledValue(label: "Description", value: bundleID.name)
                LabeledValue(label: "Platform", value: bundleID.platform.displayName)
                if let seed = bundleID.seedID {
                    LabeledValue(label: "App ID Prefix", value: seed, monospaced: true)
                }
            }
            if bundleID.isWildcard {
                Section {
                    Label("Wildcard App IDs cannot have capabilities.", systemImage: "info.circle")
                }
            } else {
                Section {
                    if isLoading {
                        ProgressView()
                    } else {
                        ForEach(CapabilityType.catalog) { type in
                            Toggle(isOn: Binding(
                                get: { capabilities.contains { $0.capabilityType == type } },
                                set: { enabled in
                                    Task {
                                        busy = type
                                        capabilities = await model.setCapability(type, enabled: enabled, bundleID: bundleID, current: capabilities)
                                        busy = nil
                                    }
                                })
                            ) {
                                HStack(spacing: 12) {
                                    Image(systemName: type.symbolName).foregroundStyle(Color.accentColor).frame(width: 24)
                                    Text(type.displayName)
                                    if busy == type { ProgressView().controlSize(.small) }
                                }
                            }
                            .disabled(busy != nil)
                        }
                    }
                } header: {
                    Text("Capabilities")
                } footer: {
                    Text("Existing profiles keep their entitlements until they are regenerated.")
                }
            }
            if !profiles.isEmpty {
                Section("Profiles") {
                    ForEach(profiles) { profile in
                        LabeledContent(profile.name) { ExpiryText(date: profile.expirationDate).font(.caption) }
                    }
                }
            }
            Section {
                Button("Delete App ID", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("App IDs used by an app in App Store Connect cannot be deleted.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(bundleID.name)
        .inlineTitle()
        .task {
            capabilities = await model.capabilities(for: bundleID)
            isLoading = false
        }
        .confirmationDialog("Delete \(bundleID.identifier)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    await model.deleteBundleID(bundleID)
                    dismiss()
                }
            }
        } message: {
            Text("Profiles for this App ID are deleted too. The identifier cannot be registered again by another team for a while.")
        }
    }
}

struct AddAppIDView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var identifier = ""
    @State private var name = ""
    @State private var platform: BundleIDPlatform = .universal
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bundle ID", text: $identifier, prompt: Text("com.example.app"))
                        .font(.body.monospaced())
                        .plainTextInput()
                        .onChange(of: identifier) { _, value in name = BundleIdentifier.suggestedName(for: value) }
                    TextField("Description", text: $name)
                    Picker("Platform", selection: $platform) {
                        Text("Universal").tag(BundleIDPlatform.universal)
                        Text("iOS").tag(BundleIDPlatform.ios)
                        Text("macOS").tag(BundleIDPlatform.macOS)
                    }
                } footer: {
                    if !identifier.isEmpty, !BundleIdentifier.isValid(identifier) {
                        Text("Use reverse-DNS letters, digits and hyphens.").foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Register App ID")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Register") {
                            Task {
                                isSaving = true
                                if await model.createBundleID(identifier: identifier, name: name, platform: platform) != nil {
                                    dismiss()
                                }
                                isSaving = false
                            }
                        }
                        .disabled(!BundleIdentifier.isValid(identifier))
                    }
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 440, minHeight: 300)
        #endif
    }
}

struct DevicesView: View {
    @Environment(AppModel.self) private var model
    @State private var isAdding = false
    @State private var renaming: Device?
    @State private var newName = ""

    private var groups: [(DeviceClass, [Device])] {
        Dictionary(grouping: model.devices, by: \.deviceClass)
            .map { ($0.key, $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.0.displayName < $1.0.displayName }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.0) { deviceClass, devices in
                    Section("\(deviceClass.displayName) (\(devices.count))") {
                        ForEach(devices) { device in
                            DeviceRow(device: device)
                                .opacity(device.status == .enabled ? 1 : 0.5)
                                .swipeActions {
                                    Button(device.status == .enabled ? "Disable" : "Enable") {
                                        Task { await model.setDevice(device, enabled: device.status != .enabled) }
                                    }
                                    .tint(device.status == .enabled ? .orange : .green)
                                    Button("Rename") {
                                        newName = device.name
                                        renaming = device
                                    }
                                }
                                .contextMenu {
                                    Button { Clipboard.copy(device.udid) } label: { Label("Copy UDID", systemImage: "doc.on.doc") }
                                    Button {
                                        newName = device.name
                                        renaming = device
                                    } label: { Label("Rename", systemImage: "pencil") }
                                    Button {
                                        Task { await model.setDevice(device, enabled: device.status != .enabled) }
                                    } label: {
                                        Label(device.status == .enabled ? "Disable" : "Enable", systemImage: device.status == .enabled ? "pause.circle" : "play.circle")
                                    }
                                }
                        }
                    }
                }
            }
            .overlay { LoadingOverlay(isEmpty: model.devices.isEmpty) }
            .adaptiveListStyle()
            .navigationTitle("Devices")
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isAdding = true } label: { Label("Register Device", systemImage: "plus") }
                        .accessibilityIdentifier("registerDevice")
                }
            }
            .sheet(isPresented: $isAdding) { RegisterDeviceView().environment(model) }
            .alert("Rename Device", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    if let device = renaming { Task { await model.rename(device, to: newName) } }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct RegisterDeviceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var udid = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Friend’s iPhone"))
                    HStack {
                        TextField("UDID", text: $udid, prompt: Text("00008150-001A2B3C4D5E6F70"))
                            .font(.body.monospaced())
                            .plainTextInput()
                        Button { if let text = Clipboard.string { udid = text } } label: { Image(systemName: "doc.on.clipboard") }
                            .buttonStyle(.borderless)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if !udid.isEmpty, !UDID.isValid(udid) {
                            Text("That doesn’t look like a UDID.").foregroundStyle(.orange)
                        }
                        Text("Find the UDID in Finder with the device connected, or in Xcode’s Devices window. Registered devices count toward the yearly limit even after you disable them.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Register Device")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Register") {
                            Task {
                                isSaving = true
                                if await model.registerDevice(name: name.isEmpty ? "Device" : name, udid: udid) != nil { dismiss() }
                                isSaving = false
                            }
                        }
                        .disabled(!UDID.isValid(udid))
                    }
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 440, minHeight: 280)
        #endif
    }
}
