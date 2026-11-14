import Foundation
import Observation
import SignKit

@MainActor
@Observable
final class CreateFlow {
    enum Step: Int, CaseIterable, Identifiable {
        case kind
        case appID
        case capabilities
        case devices
        case certificate
        case review

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .kind: "Signing Type"
            case .appID: "App ID"
            case .capabilities: "Capabilities"
            case .devices: "Devices"
            case .certificate: "Certificate"
            case .review: "Review"
            }
        }

        var symbol: String {
            switch self {
            case .kind: "hammer"
            case .appID: "app.badge"
            case .capabilities: "switch.2"
            case .devices: "iphone"
            case .certificate: "checkmark.seal"
            case .review: "list.bullet.clipboard"
            }
        }
    }

    enum AppIDMode: String, CaseIterable, Identifiable {
        case existing = "Existing"
        case new = "New"
        var id: String { rawValue }
    }

    enum Phase: Equatable {
        case editing
        case generating
        case finished(LibraryEntry)
        case failed(String)
    }

    var step: Step = .kind
    var phase: Phase = .editing
    var kind: SigningKind = .development
    var platform: SigningPlatform = .iOS
    var certificateType: CertificateType = .development

    var appIDMode: AppIDMode = .existing
    var selectedBundleID: BundleID?
    var newIdentifier = ""
    var newName = ""
    var nameWasEdited = false

    var capabilities: Set<CapabilityType> = []
    var currentCapabilities: Set<CapabilityType> = []
    var manageCapabilities = true
    var isLoadingCapabilities = false

    var selectedDeviceIDs: Set<String> = []
    var newDevices: [NewDevice] = []

    var useExistingCertificate = false
    var existingCertificate: Certificate?

    var bundleName = ""
    var bundleNameWasEdited = false
    var password = Passwords.generate()
    var progress: [GenerationStep: StepState] = [:]

    var isWildcard: Bool {
        appIDMode == .existing ? selectedBundleID?.isWildcard == true : newIdentifier.hasSuffix("*")
    }

    var identifier: String {
        appIDMode == .existing ? selectedBundleID?.identifier ?? "" : newIdentifier.trimmingCharacters(in: .whitespaces)
    }

    var appIDChoice: AppIDChoice? {
        switch appIDMode {
        case .existing:
            return selectedBundleID.map { .existing($0) }
        case .new:
            guard BundleIdentifier.isValid(identifier) else { return nil }
            return .new(identifier: identifier, name: newName.isEmpty ? BundleIdentifier.suggestedName(for: identifier) : newName)
        }
    }

    var deviceCount: Int { selectedDeviceIDs.count + newDevices.count }

    func canAdvance(from step: Step) -> Bool {
        switch step {
        case .kind: true
        case .appID: appIDChoice != nil
        case .capabilities: !isLoadingCapabilities
        case .devices: deviceCount > 0
        case .certificate: !useExistingCertificate || existingCertificate != nil
        case .review: Passwords.isAllowed(password) && !password.isEmpty && !resolvedName.isEmpty
        }
    }

    var resolvedName: String {
        let trimmed = bundleName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        let base = appIDMode == .existing ? selectedBundleID?.name ?? identifier : (newName.isEmpty ? BundleIdentifier.suggestedName(for: identifier) : newName)
        return "\(base) \(kind.title)"
    }

    func setKind(_ kind: SigningKind) {
        self.kind = kind
        if !kind.certificateTypes.contains(certificateType) {
            certificateType = kind.certificateTypes[0]
        }
        existingCertificate = nil
    }

    func setPlatform(_ platform: SigningPlatform, devices: [Device]) {
        self.platform = platform
        let allowed = Set(devices.filter(platform.accepts).map(\.id))
        selectedDeviceIDs = selectedDeviceIDs.intersection(allowed)
    }

    func request(devices: [Device]) -> SigningRequest? {
        guard let appIDChoice else { return nil }
        let certificate: CertificateChoice =
            useExistingCertificate && existingCertificate != nil
            ? .existing(existingCertificate!) : .new(type: certificateType, commonName: "SignUtils")
        return SigningRequest(
            kind: kind,
            platform: platform,
            appID: appIDChoice,
            capabilities: isWildcard ? [] : capabilities,
            manageCapabilities: manageCapabilities && !isWildcard,
            devices: devices.filter { selectedDeviceIDs.contains($0.id) },
            newDevices: newDevices,
            certificate: certificate,
            password: password,
            name: resolvedName)
    }

    func loadCapabilities(using model: AppModel) async {
        guard appIDMode == .existing, let bundleID = selectedBundleID, !bundleID.isWildcard else {
            currentCapabilities = []
            return
        }
        isLoadingCapabilities = true
        let loaded = Set(await model.capabilities(for: bundleID).map(\.capabilityType))
        currentCapabilities = loaded
        capabilities = loaded
        isLoadingCapabilities = false
    }
}
