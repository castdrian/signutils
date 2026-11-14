import SignKit
import SwiftUI

struct KindStep: View {
    @Environment(AppModel.self) private var model
    @Bindable var flow: CreateFlow

    var body: some View {
        Form {
            StepHeader(title: "How will you install it?", subtitle: "This decides the certificate and profile type.")
            Section {
                ForEach(SigningKind.allCases) { kind in
                    Button {
                        flow.setKind(kind)
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            IconBadge(
                                symbol: kind == .development ? "hammer.fill" : "shippingbox.fill",
                                color: kind == .development ? .blue : .purple, size: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(kind.title).font(.headline).foregroundStyle(.primary)
                                Text(kind.summary).font(.subheadline).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Image(systemName: flow.kind == kind ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(flow.kind == kind ? Color.accentColor : .secondary)
                        }
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("kind-\(kind.rawValue)")
                }
            }
            Section {
                Picker("Certificate type", selection: $flow.certificateType) {
                    ForEach(flow.kind.certificateTypes, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                Picker("Platform", selection: Binding(get: { flow.platform }, set: { flow.setPlatform($0, devices: model.devices) })) {
                    ForEach(SigningPlatform.allCases) { platform in
                        Text(platform.title).tag(platform)
                    }
                }
            } footer: {
                Text(flow.certificateType == .development || flow.certificateType == .distribution
                    ? "Apple Development and Apple Distribution certificates work for every platform and are what Xcode creates today."
                    : "The legacy iOS-only certificate types still work and have their own limits.")
            }
        }
        .formStyle(.grouped)
    }
}

struct AppIDStep: View {
    @Environment(AppModel.self) private var model
    @Bindable var flow: CreateFlow
    @State private var search = ""

    private var filtered: [BundleID] {
        let candidates = model.bundleIDs.filter { $0.platform != .services && $0.platform != .macOS }
        guard !search.isEmpty else { return candidates }
        return candidates.filter {
            $0.identifier.localizedCaseInsensitiveContains(search) || $0.name.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        Form {
            StepHeader(title: "Which App ID?", subtitle: "The bundle identifier you will re-sign the app with.")
            Section {
                Picker("App ID", selection: $flow.appIDMode) {
                    ForEach(CreateFlow.AppIDMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("appIDMode")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            switch flow.appIDMode {
            case .existing:
                Section {
                    TextField("Search", text: $search, prompt: Text("Search \(model.bundleIDs.count) App IDs"))
                        .plainTextInput()
                    if filtered.isEmpty {
                        Text(model.loadState == .loading ? "Loading…" : "No App IDs match.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(filtered) { bundleID in
                        Button {
                            flow.selectedBundleID = bundleID
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bundleID.name).foregroundStyle(.primary)
                                    Text(bundleID.identifier).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if bundleID.isWildcard {
                                    Pill(text: "Wildcard", color: .orange)
                                }
                                Image(systemName: flow.selectedBundleID?.id == bundleID.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(flow.selectedBundleID?.id == bundleID.id ? Color.accentColor : .secondary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("bundle-\(bundleID.identifier)")
                    }
                }
            case .new:
                Section {
                    TextField("Bundle ID", text: $flow.newIdentifier, prompt: Text("com.example.myapp"))
                        .font(.body.monospaced())
                        .plainTextInput()
                        .accessibilityIdentifier("newIdentifier")
                        .onChange(of: flow.newIdentifier) { _, value in
                            if !flow.nameWasEdited {
                                flow.newName = BundleIdentifier.suggestedName(for: value)
                            }
                        }
                    TextField("Description", text: Binding(get: { flow.newName }, set: { flow.newName = $0; flow.nameWasEdited = true }), prompt: Text("My App"))
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if !flow.newIdentifier.isEmpty, !BundleIdentifier.isValid(flow.identifier) {
                            Label("Use reverse-DNS letters, digits and hyphens, like com.example.app.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        } else if model.bundleIDs.contains(where: { $0.identifier == flow.identifier }) {
                            Label("This App ID already exists on your team. It will be reused.", systemImage: "info.circle.fill")
                        }
                        Text("End with .* for a wildcard App ID. Wildcards match any bundle identifier but cannot use capabilities.")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct CapabilitiesStep: View {
    @Bindable var flow: CreateFlow

    var body: some View {
        Form {
            StepHeader(title: "Capabilities", subtitle: "Match what the app’s entitlements need, or signing tools will strip them.")
            if flow.isWildcard {
                Section {
                    Label("Wildcard App IDs cannot have capabilities. The profile will only include basic entitlements.", systemImage: "info.circle.fill")
                }
            } else if flow.isLoadingCapabilities {
                Section {
                    HStack {
                        ProgressView()
                        Text("Reading the App ID’s capabilities…").foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    Toggle("Update capabilities on the App ID", isOn: $flow.manageCapabilities)
                    if flow.manageCapabilities {
                        HStack {
                            Button("Sideloading Essentials") {
                                flow.capabilities.formUnion(CapabilityType.sideloadingEssentials)
                            }
                            Spacer()
                            Button("Clear") { flow.capabilities = flow.capabilities.filter(\.isAlwaysOn) }
                        }
                        .buttonStyle(.borderless)
                    }
                } footer: {
                    if !flow.manageCapabilities {
                        Text("The App ID keeps the capabilities it already has.")
                    } else if flow.appIDMode == .existing {
                        Text("Changes apply to the App ID in App Store Connect and affect every profile that uses it.")
                    }
                }
                if flow.manageCapabilities {
                    Section {
                        ForEach(CapabilityType.catalog) { capability in
                            Toggle(isOn: Binding(
                                get: { flow.capabilities.contains(capability) },
                                set: { enabled in
                                    if enabled { flow.capabilities.insert(capability) } else { flow.capabilities.remove(capability) }
                                })
                            ) {
                                HStack(spacing: 12) {
                                    Image(systemName: capability.symbolName)
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 24)
                                    Text(capability.displayName)
                                    if flow.currentCapabilities.contains(capability) {
                                        Pill(text: "Enabled", color: .secondary)
                                    }
                                }
                            }
                            .accessibilityIdentifier("capability-\(capability.rawValue)")
                        }
                    } header: {
                        Text("\(flow.capabilities.count) selected")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct DevicesStep: View {
    @Environment(AppModel.self) private var model
    @Bindable var flow: CreateFlow
    @State private var newName = ""
    @State private var newUDID = ""
    @FocusState private var focus: Field?

    private enum Field {
        case name
        case udid
    }

    private var compatible: [Device] {
        model.devices.filter { flow.platform.accepts($0) && $0.status == .enabled }
    }

    private var disabled: [Device] {
        model.devices.filter { flow.platform.accepts($0) && $0.status != .enabled }
    }

    var body: some View {
        Form {
            StepHeader(title: "Which devices?", subtitle: "Only these devices will be able to install apps signed with this profile.")
            Section {
                if compatible.isEmpty {
                    Text("No enabled \(flow.platform == .tvOS ? "Apple TV" : "iPhone or iPad") devices are registered yet. Add one below.")
                        .foregroundStyle(.secondary)
                }
                ForEach(compatible) { device in
                    Button {
                        if flow.selectedDeviceIDs.contains(device.id) {
                            flow.selectedDeviceIDs.remove(device.id)
                        } else {
                            flow.selectedDeviceIDs.insert(device.id)
                        }
                    } label: {
                        DeviceRow(device: device, selected: flow.selectedDeviceIDs.contains(device.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("device-\(device.udid)")
                }
            } header: {
                HStack {
                    Text("Registered (\(flow.selectedDeviceIDs.count) of \(compatible.count))")
                    Spacer()
                    if !compatible.isEmpty {
                        Button(flow.selectedDeviceIDs.count == compatible.count ? "Deselect All" : "Select All") {
                            if flow.selectedDeviceIDs.count == compatible.count {
                                flow.selectedDeviceIDs = []
                            } else {
                                flow.selectedDeviceIDs = Set(compatible.map(\.id))
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("selectAllDevices")
                    }
                }
            }

            Section {
                ForEach(flow.newDevices, id: \.self) { device in
                    HStack {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text(UDID.normalize(device.udid)).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            flow.newDevices.removeAll { $0 == device }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                TextField("Device name", text: $newName, prompt: Text("Friend’s iPhone"))
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = .udid }
                    .accessibilityIdentifier("newDeviceName")
                HStack {
                    TextField("UDID", text: $newUDID, prompt: Text("00008150-001A2B3C4D5E6F70"))
                        .font(.body.monospaced())
                        .plainTextInput()
                        .focused($focus, equals: .udid)
                        .submitLabel(.done)
                        .onSubmit(addNewDevice)
                        .accessibilityIdentifier("newDeviceUDID")
                    Button {
                        if let text = Clipboard.string { newUDID = text }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Paste UDID")
                }
                Button(action: addNewDevice) {
                    Label("Add Device", systemImage: "plus")
                }
                .disabled(!UDID.isValid(newUDID) || isDuplicate)
                .accessibilityIdentifier("addDevice")
            } header: {
                Text("Register a new device")
            } footer: {
                if !newUDID.isEmpty, !UDID.isValid(newUDID) {
                    Label("UDIDs are 25 characters like 00008150-001A2B3C4D5E6F70, or 40 hex characters on older devices.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if isDuplicate {
                    Text("This device is already registered.")
                } else {
                    Text("New devices are registered with Apple when you generate. Each team can register 100 devices per type per membership year.")
                }
            }

            if !disabled.isEmpty {
                Section("Disabled") {
                    ForEach(disabled) { device in
                        DeviceRow(device: device, selected: false)
                            .opacity(0.5)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addNewDevice() {
        guard UDID.isValid(newUDID), !isDuplicate else { return }
        flow.newDevices.append(NewDevice(name: newName.isEmpty ? "Device" : newName, udid: UDID.normalize(newUDID)))
        newName = ""
        newUDID = ""
        focus = nil
    }

    private var isDuplicate: Bool {
        let udid = UDID.normalize(newUDID)
        return compatible.contains { UDID.normalize($0.udid) == udid } || flow.newDevices.contains { UDID.normalize($0.udid) == udid }
    }
}

struct DeviceRow: View {
    var device: Device
    var selected: Bool?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.deviceClass.symbolName)
                .font(.title3)
                .foregroundStyle(device.deviceClass.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).foregroundStyle(.primary)
                Text(device.model ?? device.deviceClass.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(device.udid)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let selected {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
        }
        .contentShape(.rect)
    }
}

struct CertificateStep: View {
    @Environment(AppModel.self) private var model
    @Bindable var flow: CreateFlow

    private var matching: [Certificate] {
        model.certificates.filter { $0.certificateType == flow.certificateType }
    }

    var body: some View {
        Form {
            StepHeader(title: "Which certificate?", subtitle: "SignUtils needs the private key to build the .p12.")
            Section {
                Button {
                    flow.useExistingCertificate = false
                    flow.existingCertificate = nil
                } label: {
                    HStack(spacing: 14) {
                        IconBadge(symbol: "plus.seal.fill", color: .green, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create a new certificate").font(.headline).foregroundStyle(.primary)
                            Text("A fresh 2048-bit key is generated on this device. Its \(flow.certificateType.displayName) certificate is valid for one year.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: !flow.useExistingCertificate ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(!flow.useExistingCertificate ? Color.accentColor : .secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("newCertificate")
            } footer: {
                if flow.certificateType.isDistribution, matching.count >= 2 {
                    Label("You already have \(matching.count) \(flow.certificateType.displayName) certificates. Apple allows at most 3, so reuse one or revoke an old one first.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                if matching.isEmpty {
                    Text("No \(flow.certificateType.displayName) certificates yet.").foregroundStyle(.secondary)
                }
                ForEach(matching) { certificate in
                    let hasKey = model.keyedCertificateIDs.contains(certificate.id)
                    Button {
                        guard hasKey else { return }
                        flow.useExistingCertificate = true
                        flow.existingCertificate = certificate
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(certificate.name).foregroundStyle(.primary).lineLimit(1)
                                HStack(spacing: 8) {
                                    if hasKey {
                                        Pill(text: "Key on this device", color: .green, symbol: "key.fill")
                                    } else {
                                        Pill(text: "Key not available", color: .secondary, symbol: "key.slash")
                                    }
                                    ExpiryText(date: certificate.expirationDate).font(.caption)
                                }
                            }
                            Spacer()
                            if hasKey {
                                let selected = flow.useExistingCertificate && flow.existingCertificate?.id == certificate.id
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                            }
                        }
                        .contentShape(.rect)
                        .opacity(hasKey ? 1 : 0.55)
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasKey)
                }
            } header: {
                Text("Reuse an existing certificate")
            } footer: {
                Text("Only certificates created by SignUtils on this device can be reused, because Apple never hands out private keys.")
            }
        }
        .formStyle(.grouped)
    }
}

struct ReviewStep: View {
    @Environment(AppModel.self) private var model
    @Bindable var flow: CreateFlow

    var body: some View {
        Form {
            StepHeader(title: "Review", subtitle: "Everything below is created in App Store Connect when you tap Generate.")
            Section {
                TextField("Bundle name", text: $flow.bundleName, prompt: Text(flow.resolvedName))
                    .accessibilityIdentifier("bundleName")
                HStack {
                    TextField("P12 password", text: $flow.password)
                        .font(.body.monospaced())
                        .plainTextInput()
                        .accessibilityIdentifier("password")
                    Button {
                        flow.password = Passwords.generate()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Generate a new password")
                }
            } header: {
                Text("Archive")
            } footer: {
                if !Passwords.isAllowed(flow.password) {
                    Label("Use only ASCII letters, digits, spaces and symbols so every signing tool can open the .p12.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if flow.password.isEmpty {
                    Text("Some signing tools refuse .p12 files without a password.")
                }
            }

            Section("Summary") {
                SummaryRow(symbol: "hammer", title: "Signing", value: "\(flow.kind.title), \(flow.certificateType.displayName)")
                SummaryRow(symbol: "app.badge", title: "App ID", value: flow.identifier + (flow.appIDMode == .new ? " (new)" : ""))
                SummaryRow(
                    symbol: "switch.2", title: "Capabilities",
                    value: flow.isWildcard ? "None (wildcard)" : !flow.manageCapabilities ? "Unchanged" : flow.capabilities.isEmpty ? "None" : flow.capabilities.sorted().map(\.displayName).joined(separator: ", "))
                SummaryRow(
                    symbol: "iphone", title: "Devices",
                    value: "\(flow.deviceCount) device\(flow.deviceCount == 1 ? "" : "s")" + (flow.newDevices.isEmpty ? "" : ", \(flow.newDevices.count) new"))
                SummaryRow(
                    symbol: "checkmark.seal", title: "Certificate",
                    value: flow.useExistingCertificate ? "Reuse \(flow.existingCertificate?.name ?? "")" : "New \(flow.certificateType.displayName)")
                SummaryRow(symbol: "doc.badge.gearshape", title: "Profile", value: flow.kind.profileType(for: flow.platform).displayName)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SummaryRow: View {
    var symbol: String
    var title: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 22)
            Text(title)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
