import SignKit
import SwiftUI

struct CreateBundleView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var flow = CreateFlow()

    var body: some View {
        NavigationStack {
            Group {
                switch flow.phase {
                case .editing:
                    VStack(spacing: 0) {
                        StepIndicator(current: flow.step)
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                        stepContent
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .safeAreaInset(edge: .bottom) { bottomBar }
                case .generating, .failed, .finished:
                    GenerationView(flow: flow, onRetry: generate, onDone: { dismiss() })
                }
            }
            .navigationTitle(flow.phase == .editing ? flow.step.title : "New Signing Bundle")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if flow.phase != .generating {
                        Button(isFinished ? "Done" : "Cancel") { dismiss() }
                            .accessibilityIdentifier("closeCreate")
                    }
                }
            }
            .interactiveDismissDisabled(flow.phase == .generating)
            .animation(.snappy, value: flow.step)
            .animation(.snappy, value: flow.phase)
        }
        #if os(macOS)
            .frame(minWidth: 620, idealWidth: 680, minHeight: 640, idealHeight: 720)
        #endif
    }

    private var isFinished: Bool {
        if case .finished = flow.phase { return true }
        return false
    }

    @ViewBuilder
    private var stepContent: some View {
        switch flow.step {
        case .kind: KindStep(flow: flow)
        case .appID: AppIDStep(flow: flow)
        case .capabilities: CapabilitiesStep(flow: flow)
        case .devices: DevicesStep(flow: flow)
        case .certificate: CertificateStep(flow: flow)
        case .review: ReviewStep(flow: flow)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if flow.step != .kind {
                Button {
                    flow.step = CreateFlow.Step(rawValue: flow.step.rawValue - 1) ?? .kind
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("back")
            }
            Spacer()
            if flow.step == .review {
                Button(action: generate) {
                    Label("Generate", systemImage: "wand.and.stars")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!flow.canAdvance(from: .review))
                .accessibilityIdentifier("generate")
            } else {
                Button(action: advance) {
                    HStack {
                        Text("Continue")
                        Image(systemName: "chevron.right")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!flow.canAdvance(from: flow.step))
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("continue")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func advance() {
        let next = CreateFlow.Step(rawValue: flow.step.rawValue + 1) ?? .review
        if flow.step == .appID {
            Task { await flow.loadCapabilities(using: model) }
        }
        flow.step = next
    }

    private func generate() {
        guard let generator = model.generator(), let request = flow.request(devices: model.devices) else { return }
        flow.progress = [:]
        flow.phase = .generating
        Task {
            do {
                let artifacts = try await generator.generate(request) { step, state in
                    Task { @MainActor in flow.progress[step] = state }
                }
                let entry = try model.store(artifacts)
                try? await Task.sleep(for: .milliseconds(150))
                flow.phase = .finished(entry)
                await model.refresh()
            } catch {
                flow.phase = .failed(error.localizedDescription)
                await model.refresh()
            }
        }
    }
}

struct StepIndicator: View {
    var current: CreateFlow.Step

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CreateFlow.Step.allCases) { step in
                Capsule()
                    .fill(step.rawValue <= current.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(height: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current.rawValue + 1) of \(CreateFlow.Step.allCases.count): \(current.title)")
    }
}

struct StepHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
    }
}
