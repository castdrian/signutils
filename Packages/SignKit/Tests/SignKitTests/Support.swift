import Foundation
import Testing

@testable import SignKit

struct CommandResult {
    var status: Int32
    var output: String
}

@discardableResult
func run(_ executable: String, _ arguments: [String], input: Data? = nil) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    if let input {
        let inputPipe = Pipe()
        process.standardInput = inputPipe
        try process.run()
        inputPipe.fileHandleForWriting.write(input)
        try inputPipe.fileHandleForWriting.close()
    } else {
        try process.run()
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
}

func openssl() -> String {
    for path in ["/opt/homebrew/bin/openssl", "/usr/local/bin/openssl", "/usr/bin/openssl"]
    where FileManager.default.isExecutableFile(atPath: path) {
        return path
    }
    return "/usr/bin/openssl"
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("signkit-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func selfSignedCertificate(for keyPair: RSAKeyPair, commonName: String = "SignKit Test") throws -> Data {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let keyURL = directory.appendingPathComponent("key.pem")
    let certURL = directory.appendingPathComponent("cert.der")
    try keyPair.privateKeyPEM.write(to: keyURL, atomically: true, encoding: .utf8)
    let result = try run(
        openssl(),
        [
            "req", "-new", "-x509", "-key", keyURL.path, "-subj", "/CN=\(commonName)/OU=TEAMID1234", "-days", "30",
            "-outform", "DER", "-out", certURL.path,
        ])
    #expect(result.status == 0, "\(result.output)")
    return try Data(contentsOf: certURL)
}

func sampleProfile(certificates: [Data], devices: [String], teamID: String = "TEAMID1234", bundleID: String)
    throws -> Data
{
    let plist: [String: Any] = [
        "Name": "Sample Profile",
        "UUID": "11111111-2222-3333-4444-555555555555",
        "TeamIdentifier": [teamID],
        "TeamName": "Sample Team",
        "AppIDName": "Sample",
        "CreationDate": Date(timeIntervalSince1970: 1_800_000_000),
        "ExpirationDate": Date(timeIntervalSince1970: 1_830_000_000),
        "ProvisionedDevices": devices,
        "DeveloperCertificates": certificates,
        "Entitlements": [
            "application-identifier": "\(teamID).\(bundleID)",
            "get-task-allow": true,
            "com.apple.developer.team-identifier": teamID,
        ],
    ]
    let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    return Data([0x30, 0x80, 0x06, 0x09]) + xml + Data([0x00, 0x00, 0xA0, 0x82])
}
