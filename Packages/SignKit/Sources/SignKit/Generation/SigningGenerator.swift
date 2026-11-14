import Foundation

public enum GenerationStep: String, CaseIterable, Sendable, Identifiable {
    case appID
    case capabilities
    case devices
    case certificate
    case profile
    case package

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appID: "App ID"
        case .capabilities: "Capabilities"
        case .devices: "Devices"
        case .certificate: "Certificate"
        case .profile: "Provisioning profile"
        case .package: "Archive"
        }
    }

    public var symbolName: String {
        switch self {
        case .appID: "app.badge"
        case .capabilities: "switch.2"
        case .devices: "iphone"
        case .certificate: "checkmark.seal"
        case .profile: "doc.badge.gearshape"
        case .package: "doc.zipper"
        }
    }
}

public enum StepState: Sendable, Equatable {
    case pending
    case running(String)
    case done(String)
    case skipped(String)
    case failed(String)
}

public enum GenerationError: Error, LocalizedError, Equatable {
    case missingPrivateKey(String)
    case noDevices
    case invalidUDID(String)
    case invalidBundleIdentifier(String)
    case invalidPassword
    case certificateMissingContent
    case profileMissingContent
    case profileDoesNotMatch

    public var errorDescription: String? {
        switch self {
        case .missingPrivateKey(let name):
            "SignUtils does not have the private key for \(name). Pick a certificate that SignUtils created on this device, or create a new one."
        case .noDevices: "Select at least one device for this profile."
        case .invalidUDID(let udid): "\(udid) is not a valid device UDID."
        case .invalidBundleIdentifier(let identifier): "\(identifier) is not a valid bundle identifier."
        case .invalidPassword: "Use only letters, digits, spaces and ASCII symbols in the P12 password so every signing tool can open it."
        case .certificateMissingContent: "Apple did not return the certificate contents."
        case .profileMissingContent: "Apple did not return the provisioning profile contents."
        case .profileDoesNotMatch: "The provisioning profile does not contain the selected certificate."
        }
    }
}

public struct SigningGenerator: Sendable {
    public typealias Progress = @Sendable (GenerationStep, StepState) -> Void

    private let service: AppStoreConnectService
    private let keys: PrivateKeyVault
    private let credentialsKeyID: String

    public init(service: AppStoreConnectService, keys: PrivateKeyVault, credentialsKeyID: String) {
        self.service = service
        self.keys = keys
        self.credentialsKeyID = credentialsKeyID
    }

    public func validate(_ request: SigningRequest) throws {
        guard BundleIdentifier.isValid(request.appID.identifier) else {
            throw GenerationError.invalidBundleIdentifier(request.appID.identifier)
        }
        for device in request.newDevices where !UDID.isValid(device.udid) {
            throw GenerationError.invalidUDID(device.udid)
        }
        guard Passwords.isAllowed(request.password) else {
            throw GenerationError.invalidPassword
        }
        guard !(request.devices.isEmpty && request.newDevices.isEmpty) else {
            throw GenerationError.noDevices
        }
    }

    public func generate(_ request: SigningRequest, progress: Progress = { _, _ in }) async throws
        -> SigningArtifacts
    {
        try validate(request)
        var createdCertificateID: String?
        do {
            let bundleID = try await resolveAppID(request, progress: progress)
            let capabilities = try await applyCapabilities(request, bundleID: bundleID, progress: progress)
            let devices = try await resolveDevices(request, progress: progress)
            let (certificate, keyPair, created) = try await resolveCertificate(request, progress: progress)
            if created { createdCertificateID = certificate.id }
            let profile = try await createProfile(
                request, bundleID: bundleID, certificate: certificate, devices: devices, progress: progress)
            let artifacts = try package(
                request, bundleID: bundleID, capabilities: capabilities, devices: devices, certificate: certificate,
                keyPair: keyPair, profile: profile, progress: progress)
            return artifacts
        } catch {
            if let createdCertificateID {
                try? await service.revokeCertificate(id: createdCertificateID)
                try? keys.remove(certificateID: createdCertificateID)
            }
            throw error
        }
    }

    private func resolveAppID(_ request: SigningRequest, progress: Progress) async throws -> BundleID {
        switch request.appID {
        case .existing(let bundleID):
            progress(.appID, .done(bundleID.identifier))
            return bundleID
        case .new(let identifier, let name):
            progress(.appID, .running("Registering \(identifier)"))
            do {
                let created = try await service.createBundleID(
                    identifier: identifier, name: BundleIdentifier.apiName(name), platform: .universal)
                progress(.appID, .done("Registered \(identifier)"))
                return created
            } catch let error as AppStoreConnectError where error.isConflict {
                if let existing = try await service.bundleIDs().first(where: { $0.identifier == identifier }) {
                    progress(.appID, .done("Using existing \(identifier)"))
                    return existing
                }
                progress(.appID, .failed(error.localizedDescription))
                throw error
            } catch {
                progress(.appID, .failed(error.localizedDescription))
                throw error
            }
        }
    }

    private func applyCapabilities(_ request: SigningRequest, bundleID: BundleID, progress: Progress) async throws
        -> [CapabilityType]
    {
        guard !bundleID.isWildcard else {
            progress(.capabilities, .skipped("Wildcard App IDs cannot have capabilities"))
            return []
        }
        progress(.capabilities, .running("Reading capabilities"))
        do {
            var current = try await service.capabilities(bundleID: bundleID.id)
            guard request.manageCapabilities else {
                progress(.capabilities, .skipped("Left unchanged"))
                return current.map(\.capabilityType).sorted()
            }
            let currentTypes = Set(current.map(\.capabilityType))
            let toEnable = request.capabilities.subtracting(currentTypes).sorted()
            let toDisable = current.filter {
                !request.capabilities.contains($0.capabilityType) && !$0.capabilityType.isAlwaysOn
                    && CapabilityType.catalog.contains($0.capabilityType)
            }
            for type in toEnable {
                progress(.capabilities, .running("Enabling \(type.displayName)"))
                let capability = try await service.enableCapability(
                    type, settings: type.defaultSettings, bundleID: bundleID.id)
                current.append(capability)
            }
            for capability in toDisable {
                progress(.capabilities, .running("Disabling \(capability.capabilityType.displayName)"))
                try await service.disableCapability(id: capability.id)
                current.removeAll { $0.id == capability.id }
            }
            let summary =
                toEnable.isEmpty && toDisable.isEmpty
                ? "Already up to date" : "\(toEnable.count) enabled, \(toDisable.count) disabled"
            progress(.capabilities, .done(summary))
            return current.map(\.capabilityType).sorted()
        } catch {
            progress(.capabilities, .failed(error.localizedDescription))
            throw error
        }
    }

    private func resolveDevices(_ request: SigningRequest, progress: Progress) async throws -> [Device] {
        guard request.kind.profileType(for: request.platform).includesDevices else {
            progress(.devices, .skipped("This profile type has no device list"))
            return []
        }
        progress(.devices, .running("Checking devices"))
        do {
            var devices = request.devices
            if !request.newDevices.isEmpty {
                let registered = try await service.devices()
                for newDevice in request.newDevices {
                    let udid = UDID.normalize(newDevice.udid)
                    if let existing = registered.first(where: { UDID.normalize($0.udid) == udid }) {
                        var device = existing
                        if existing.status == .disabled {
                            progress(.devices, .running("Enabling \(existing.name)"))
                            device = try await service.updateDevice(id: existing.id, name: nil, status: .enabled)
                        }
                        devices.append(device)
                    } else {
                        progress(.devices, .running("Registering \(newDevice.name)"))
                        devices.append(try await service.registerDevice(name: newDevice.name, udid: udid, platform: .ios))
                    }
                }
            }
            var seen = Set<String>()
            devices = devices.filter { seen.insert($0.id).inserted }
            progress(.devices, .done(devices.count == 1 ? devices[0].name : "\(devices.count) devices"))
            return devices
        } catch {
            progress(.devices, .failed(error.localizedDescription))
            throw error
        }
    }

    private func resolveCertificate(_ request: SigningRequest, progress: Progress) async throws
        -> (Certificate, RSAKeyPair, Bool)
    {
        switch request.certificate {
        case .existing(let certificate):
            progress(.certificate, .running("Loading \(certificate.displayName)"))
            guard let keyPair = try keys.keyPair(certificateID: certificate.id) else {
                let error = GenerationError.missingPrivateKey(certificate.displayName)
                progress(.certificate, .failed(error.localizedDescription))
                throw error
            }
            var resolved = certificate
            if resolved.content == nil {
                resolved = try await service.certificate(id: certificate.id)
            }
            guard resolved.content != nil else { throw GenerationError.certificateMissingContent }
            progress(.certificate, .done("Reusing \(certificate.certificateType.displayName)"))
            return (resolved, keyPair, false)
        case .new(let type, let commonName):
            do {
                progress(.certificate, .running("Generating a 2048-bit RSA key"))
                let keyPair = try RSAKeyPair.generate()
                let csr = try CertificateSigningRequest(keyPair: keyPair, commonName: commonName)
                progress(.certificate, .running("Requesting \(type.displayName) certificate"))
                let certificate = try await service.createCertificate(type: type, csr: csr)
                guard let content = certificate.content, keyPair.matches(certificateDER: content) else {
                    try? await service.revokeCertificate(id: certificate.id)
                    throw GenerationError.certificateMissingContent
                }
                try keys.save(keyPair, certificateID: certificate.id)
                progress(.certificate, .done("Created \(type.displayName)"))
                return (certificate, keyPair, true)
            } catch {
                progress(.certificate, .failed(error.localizedDescription))
                throw error
            }
        }
    }

    private func createProfile(
        _ request: SigningRequest, bundleID: BundleID, certificate: Certificate, devices: [Device],
        progress: Progress
    ) async throws -> Profile {
        let type = request.kind.profileType(for: request.platform)
        progress(.profile, .running("Creating \(type.displayName) profile"))
        let baseName = BundleIdentifier.apiName(request.name)
        do {
            var profile: Profile
            do {
                profile = try await service.createProfile(
                    name: baseName, type: type, bundleID: bundleID.id, certificateIDs: [certificate.id],
                    deviceIDs: devices.map(\.id))
            } catch let error as AppStoreConnectError where error.isConflict && Self.isDuplicateName(error) {
                let stamp = Self.stampFormatter.string(from: Date())
                profile = try await service.createProfile(
                    name: "\(baseName) \(stamp)", type: type, bundleID: bundleID.id, certificateIDs: [certificate.id],
                    deviceIDs: devices.map(\.id))
            }
            if profile.content == nil {
                profile = try await service.profile(id: profile.id)
            }
            guard let content = profile.content else { throw GenerationError.profileMissingContent }
            let parsed = try ProvisioningProfile(data: content)
            guard let certificateContent = certificate.content, parsed.contains(certificateDER: certificateContent) else {
                throw GenerationError.profileDoesNotMatch
            }
            progress(.profile, .done(profile.name))
            return profile
        } catch {
            progress(.profile, .failed(error.localizedDescription))
            throw error
        }
    }

    private func package(
        _ request: SigningRequest, bundleID: BundleID, capabilities: [CapabilityType], devices: [Device],
        certificate: Certificate, keyPair: RSAKeyPair, profile: Profile, progress: Progress
    ) throws -> SigningArtifacts {
        progress(.package, .running("Building the PKCS#12 container"))
        do {
            guard let certificateDER = certificate.content else { throw GenerationError.certificateMissingContent }
            guard let profileData = profile.content else { throw GenerationError.profileMissingContent }
            let parsedProfile = try ProvisioningProfile(data: profileData)
            let info = try CertificateInfo(der: certificateDER)
            let p12 = try PKCS12(
                certificateDER: certificateDER, privateKeyPKCS8: keyPair.privateKeyPKCS8, password: request.password,
                friendlyName: info.commonName)
            let createdAt = Date()
            let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
            var bundle = SigningBundle(
                name: name.isEmpty ? bundleID.identifier : name,
                createdAt: createdAt,
                kind: request.kind,
                platform: request.platform,
                teamID: parsedProfile.teamIdentifier,
                teamName: parsedProfile.teamName,
                bundleIdentifier: bundleID.identifier,
                bundleIDResource: bundleID.id,
                capabilities: capabilities,
                devices: devices.map {
                    SigningBundle.DeviceSummary(name: $0.name, udid: $0.udid, deviceClass: $0.deviceClass)
                },
                certificateID: certificate.id,
                certificateType: certificate.certificateType,
                certificateName: info.commonName,
                certificateSerial: info.serialNumber,
                certificateExpiration: certificate.expirationDate ?? info.notAfter,
                profileID: profile.id,
                profileUUID: parsedProfile.uuid,
                profileName: profile.name,
                profileType: profile.profileType,
                profileExpiration: profile.expirationDate ?? parsedProfile.expirationDate,
                password: request.password,
                fileName: "",
                credentialsKeyID: credentialsKeyID)
            bundle.fileName = "\(bundle.archiveBaseName)-\(bundle.id.uuidString.prefix(8)).zip"
            progress(.package, .running("Writing the archive"))
            let archive = try ZipArchive.make(
                SigningArchive.entries(
                    bundle: bundle, p12: p12.der, profile: profileData, certificate: certificateDER,
                    createdAt: createdAt))
            progress(.package, .done(bundle.fileName))
            return SigningArtifacts(
                bundle: bundle, archive: archive, p12: p12.der, profile: profileData, certificate: certificateDER)
        } catch {
            progress(.package, .failed(error.localizedDescription))
            throw error
        }
    }

    private static func isDuplicateName(_ error: AppStoreConnectError) -> Bool {
        error.items.contains { ($0.detail ?? "").localizedCaseInsensitiveContains("name") }
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd HHmmss"
        return formatter
    }()
}
