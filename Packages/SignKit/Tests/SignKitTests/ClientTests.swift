import CryptoKit
import Foundation
import Testing

@testable import SignKit

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handlers: [String: (URLRequest) -> (Int, Data)] = [:]
    nonisolated(unsafe) static var requests: [String: [URLRequest]] = [:]
    static let lock = NSLock()

    static func register(_ token: String, handler: @escaping (URLRequest) -> (Int, Data)) {
        lock.withLock { handlers[token] = handler }
    }

    static func recorded(_ token: String) -> [URLRequest] {
        lock.withLock { requests[token] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let token = request.url?.host ?? ""
        var captured = request
        if let stream = request.httpBodyStream {
            stream.open()
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
            captured.httpBody = body
        }
        let handler = Self.lock.withLock { () -> ((URLRequest) -> (Int, Data))? in
            Self.requests[token, default: []].append(captured)
            return Self.handlers[token]
        }
        let (status, data) = handler?(captured) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("App Store Connect client")
struct ClientTests {
    private func makeClient(_ handler: @escaping (URLRequest) -> (Int, Data)) -> (AppStoreConnectClient, String) {
        let token = "stub-\(UUID().uuidString.lowercased())"
        StubProtocol.register(token, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let credentials = APICredentials(
            name: "Test", keyID: "ABCDE12345", issuerID: UUID().uuidString,
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation)
        let client = AppStoreConnectClient(
            credentials: credentials, session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://\(token)")!)
        return (client, token)
    }

    @Test func followsPaginationAndDecodesDevices() async throws {
        let (client, token) = makeClient { request in
            let url = request.url!.absoluteString
            if url.contains("cursor=2") {
                return (200, Data(#"{"data":[{"id":"D2","type":"devices","attributes":{"name":"iPad","udid":"U2","platform":"IOS","deviceClass":"IPAD","status":"DISABLED","addedDate":"2025-01-02T03:04:05.000+00:00"}}],"links":{}}"#.utf8))
            }
            let next = "https://\(request.url!.host!)/v1/devices?cursor=2"
            return (200, Data(#"{"data":[{"id":"D1","type":"devices","attributes":{"name":"iPhone","udid":"U1","platform":"IOS","deviceClass":"IPHONE","status":"ENABLED","model":"iPhone 17"}}],"links":{"next":"\#(next)"}}"#.utf8))
        }
        let devices = try await client.devices()
        #expect(devices.map(\.id) == ["D1", "D2"])
        #expect(devices[1].status == .disabled)
        #expect(devices[1].deviceClass == .iPad)
        #expect(devices[1].addedDate != nil)
        let requests = StubProtocol.recorded(token)
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ey") == true)
        #expect(requests[0].url!.query!.contains("limit=200"))
    }

    @Test func createsCertificatesWithCSRContent() async throws {
        let (client, token) = makeClient { _ in
            (201, Data(#"{"data":{"id":"C1","type":"certificates","attributes":{"name":"Apple Development: X","displayName":"X","certificateType":"DEVELOPMENT","serialNumber":"ABC","expirationDate":"2027-01-01T00:00:00.000+00:00","certificateContent":"AQID"}}}"#.utf8))
        }
        let keyPair = try RSAKeyPair.generate()
        let csr = try CertificateSigningRequest(keyPair: keyPair, commonName: "X")
        let certificate = try await client.createCertificate(type: .development, csr: csr)
        #expect(certificate.content == Data([1, 2, 3]))
        #expect(certificate.certificateType == .development)
        let request = StubProtocol.recorded(token)[0]
        #expect(request.httpMethod == "POST")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: Any]
        let data = body["data"] as! [String: Any]
        let attributes = data["attributes"] as! [String: Any]
        #expect(data["type"] as? String == "certificates")
        #expect(attributes["certificateType"] as? String == "DEVELOPMENT")
        #expect(attributes["csrContent"] as? String == csr.der.base64EncodedString())
    }

    @Test func createsProfilesWithRelationships() async throws {
        let (client, token) = makeClient { _ in
            (201, Data(#"{"data":{"id":"P1","type":"profiles","attributes":{"name":"N","profileType":"IOS_APP_DEVELOPMENT","profileState":"ACTIVE","uuid":"U","expirationDate":"2027-01-01T00:00:00Z","profileContent":"AQID"}}}"#.utf8))
        }
        let profile = try await client.createProfile(
            name: "N", type: .iosAppDevelopment, bundleID: "B1", certificateIDs: ["C1"], deviceIDs: ["D1", "D2"])
        #expect(profile.content == Data([1, 2, 3]))
        #expect(profile.bundleIDResource == "B1")
        let body = try JSONSerialization.jsonObject(with: StubProtocol.recorded(token)[0].httpBody ?? Data()) as! [String: Any]
        let relationships = (body["data"] as! [String: Any])["relationships"] as! [String: Any]
        let devices = (relationships["devices"] as! [String: Any])["data"] as! [[String: String]]
        #expect(devices.map { $0["id"] } == ["D1", "D2"])
        #expect(devices.allSatisfy { $0["type"] == "devices" })
        let bundle = (relationships["bundleId"] as! [String: Any])["data"] as! [String: String]
        #expect(bundle == ["type": "bundleIds", "id": "B1"])
    }

    @Test func adHocStoreProfilesOmitDevicesWhenNotNeeded() async throws {
        let (client, token) = makeClient { _ in
            (201, Data(#"{"data":{"id":"P1","type":"profiles","attributes":{"name":"N","profileType":"IOS_APP_STORE","profileState":"ACTIVE","uuid":"U"}}}"#.utf8))
        }
        _ = try await client.createProfile(
            name: "N", type: .iosAppStore, bundleID: "B1", certificateIDs: ["C1"], deviceIDs: ["D1"])
        let body = try JSONSerialization.jsonObject(with: StubProtocol.recorded(token)[0].httpBody ?? Data()) as! [String: Any]
        let relationships = (body["data"] as! [String: Any])["relationships"] as! [String: Any]
        #expect(relationships["devices"] == nil)
    }

    @Test func enablesCapabilitiesWithSettings() async throws {
        let (client, token) = makeClient { _ in
            (201, Data(#"{"data":{"id":"B1_ICLOUD","type":"bundleIdCapabilities","attributes":{"capabilityType":"ICLOUD","settings":[{"key":"ICLOUD_VERSION","options":[{"key":"XCODE_6","enabled":true}]}]}}}"#.utf8))
        }
        let capability = try await client.enableCapability(.iCloud, settings: CapabilityType.iCloud.defaultSettings, bundleID: "B1")
        #expect(capability.capabilityType == .iCloud)
        #expect(capability.settings.first?.key == "ICLOUD_VERSION")
        let body = String(decoding: StubProtocol.recorded(token)[0].httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("ICLOUD_VERSION"))
        #expect(body.contains("XCODE_6"))
    }

    @Test func surfacesAppleErrors() async throws {
        let (client, _) = makeClient { _ in
            (409, Data(#"{"errors":[{"status":"409","code":"ENTITY_ERROR","title":"Problem","detail":"You already have a current Apple Distribution certificate."}]}"#.utf8))
        }
        do {
            _ = try await client.certificates()
            Issue.record("Expected an error")
        } catch let error as AppStoreConnectError {
            #expect(error.statusCode == 409)
            #expect(error.isConflict)
            #expect(error.localizedDescription == "You already have a current Apple Distribution certificate.")
        }
    }

    @Test func revokesWithDelete() async throws {
        let (client, token) = makeClient { _ in (204, Data()) }
        try await client.revokeCertificate(id: "C9")
        try await client.deleteProfile(id: "P9")
        try await client.deleteBundleID(id: "B9")
        try await client.disableCapability(id: "B9_ICLOUD")
        let requests = StubProtocol.recorded(token)
        #expect(requests.map(\.httpMethod) == ["DELETE", "DELETE", "DELETE", "DELETE"])
        #expect(requests.map(\.url!.path) == [
            "/v1/certificates/C9", "/v1/profiles/P9", "/v1/bundleIds/B9", "/v1/bundleIdCapabilities/B9_ICLOUD",
        ])
    }

    @Test func updatesDevicesWithPatch() async throws {
        let (client, token) = makeClient { _ in
            (200, Data(#"{"data":{"id":"D1","type":"devices","attributes":{"name":"Renamed","udid":"U","platform":"IOS","deviceClass":"IPHONE","status":"DISABLED"}}}"#.utf8))
        }
        let device = try await client.updateDevice(id: "D1", name: "Renamed", status: .disabled)
        #expect(device.status == .disabled)
        let request = StubProtocol.recorded(token)[0]
        #expect(request.httpMethod == "PATCH")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: Any]
        #expect((body["data"] as! [String: Any])["id"] as? String == "D1")
    }
}
