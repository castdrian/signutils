import SignKit
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

extension View {
    @ViewBuilder
    func glassBackground<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func inlineTitle() -> some View {
        #if os(iOS)
            navigationBarTitleDisplayMode(.inline)
        #else
            self
        #endif
    }

    @ViewBuilder
    func plainTextInput() -> some View {
        #if os(iOS)
            textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
            autocorrectionDisabled()
        #endif
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        #if os(iOS)
            UIPasteboard.general.string = text
        #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    static var string: String? {
        #if os(iOS)
            UIPasteboard.general.string
        #else
            NSPasteboard.general.string(forType: .string)
        #endif
    }
}

struct Pill: View {
    var text: String
    var color: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: .capsule)
    }
}

struct StatusPill: View {
    var status: LibraryEntry.Status

    var body: some View {
        switch status {
        case .active: Pill(text: "Active", color: .green, symbol: "checkmark.circle.fill")
        case .expired: Pill(text: "Expired", color: .orange, symbol: "clock.badge.exclamationmark")
        case .certificateRevoked: Pill(text: "Certificate revoked", color: .red, symbol: "xmark.seal.fill")
        case .profileDeleted: Pill(text: "Profile deleted", color: .orange, symbol: "doc.badge.ellipsis")
        case .profileInvalid: Pill(text: "Profile invalid", color: .orange, symbol: "exclamationmark.triangle.fill")
        case .revoked: Pill(text: "Revoked", color: .red, symbol: "xmark.octagon.fill")
        }
    }
}

struct KindPill: View {
    var kind: SigningKind

    var body: some View {
        Pill(text: kind.title, color: kind == .development ? .blue : .purple, symbol: kind == .development ? "hammer.fill" : "shippingbox.fill")
    }
}

struct ExpiryText: View {
    var date: Date?

    var body: some View {
        if let date {
            let days = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
            Group {
                if date < .now {
                    Text("Expired \(date, format: .relative(presentation: .named))")
                        .foregroundStyle(.red)
                } else if days < 30 {
                    Text("Expires \(date, format: .relative(presentation: .named))")
                        .foregroundStyle(.orange)
                } else {
                    Text("Expires \(date, format: .dateTime.day().month(.abbreviated).year())")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct IconBadge: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct LabeledValue: View {
    var label: String
    var value: String
    var monospaced = false
    var copyable = false

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                Text(value)
                    .font(monospaced ? .callout.monospaced() : .callout)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                if copyable {
                    Button {
                        Clipboard.copy(value)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy \(label)")
                }
            }
        }
    }
}

struct LoadingOverlay: View {
    @Environment(AppModel.self) private var model
    var isEmpty: Bool

    var body: some View {
        if isEmpty, model.loadState == .loading {
            ProgressView("Loading from App Store Connect…")
                .padding(24)
                .glassBackground(in: .rect(cornerRadius: 20))
        } else if isEmpty, case .failed(let message) = model.loadState {
            ContentUnavailableView {
                Label("Couldn’t reach App Store Connect", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await model.refresh() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct RefreshButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            Task { await model.refresh() }
        } label: {
            if model.loadState == .loading {
                ProgressView().controlSize(.small)
            } else {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .disabled(model.loadState == .loading)
        .accessibilityIdentifier("refresh")
    }
}

struct DemoBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isDemo, !ProcessInfo.processInfo.arguments.contains("-screenshots") {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Demo mode").font(.subheadline.weight(.semibold))
                        Text("Nothing here touches a real account.").font(.caption).opacity(0.85)
                    }
                    Spacer()
                    Button("Exit") { Task { await model.leaveDemo() } }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .controlSize(.small)
                }
                .foregroundStyle(.white)
                .listRowBackground(Rectangle().fill(Color.indigo.gradient))
            }
        }
    }
}

struct ExportedFile: Transferable {
    var url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { file in
            SentTransferredFile(file.url)
        }
    }
}

struct DataDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.data]
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static let mobileProvision = UTType(filenameExtension: "mobileprovision") ?? .data
    static let p8Key = UTType(filenameExtension: "p8") ?? .data
}

func temporaryFile(named name: String, data: Data) -> URL? {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    do {
        try data.write(to: url, options: .atomic)
        return url
    } catch {
        return nil
    }
}

extension DeviceClass {
    var tint: Color {
        switch self {
        case .iPhone: .blue
        case .iPad: .teal
        case .appleTV: .gray
        case .mac: .indigo
        case .appleWatch: .pink
        case .appleVisionPro: .purple
        default: .secondary
        }
    }
}

extension CertificateType {
    var tint: Color {
        switch self {
        case .development, .iosDevelopment, .macAppDevelopment: .blue
        case .distribution, .iosDistribution: .purple
        case .developerIDApplication, .developerIDApplicationG2, .developerIDKext: .orange
        default: .gray
        }
    }
}
