import SignKit
import SwiftUI

struct GenerationView: View {
    @Environment(AppModel.self) private var model
    var flow: CreateFlow
    var onRetry: () -> Void
    var onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                VStack(spacing: 0) {
                    ForEach(GenerationStep.allCases) { step in
                        ProgressRow(step: step, state: flow.progress[step] ?? .pending)
                        if step != GenerationStep.allCases.last {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .padding(.vertical, 6)
                .background(.background.secondary, in: .rect(cornerRadius: 16))
                actions
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var header: some View {
        switch flow.phase {
        case .finished(let entry):
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: entry.id)
                Text("Signing bundle ready").font(.title.bold())
                Text("\(entry.bundle.name) is in your library.")
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("generationSucceeded")
        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                Text("Something went wrong").font(.title2.bold())
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                Text("A certificate created during this attempt has already been revoked.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityIdentifier("generationFailed")
        default:
            VStack(spacing: 10) {
                ProgressView().controlSize(.large)
                Text("Talking to Apple…").font(.title2.bold())
                Text("This usually takes a few seconds.").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch flow.phase {
        case .finished(let entry):
            VStack(spacing: 12) {
                if let url = model.archiveURL(for: entry) {
                    ShareLink(item: url) {
                        Label("Share Archive", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                Button {
                    Clipboard.copy(entry.bundle.password)
                    model.toast = Toast("Password copied", symbol: "doc.on.doc.fill")
                } label: {
                    Label("Copy Password", systemImage: "key")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Button("Done", action: onDone)
                    .controlSize(.large)
                    .accessibilityIdentifier("finish")
            }
        case .failed:
            HStack(spacing: 12) {
                Button {
                    flow.phase = .editing
                } label: {
                    Text("Edit").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                Button(action: onRetry) {
                    Text("Try Again").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        default:
            EmptyView()
        }
    }
}

private struct ProgressRow: View {
    var step: GenerationStep
    var state: StepState

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                switch state {
                case .pending:
                    Image(systemName: step.symbolName).foregroundStyle(.tertiary)
                case .running:
                    ProgressView().controlSize(.small)
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .skipped:
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                case .failed:
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            .font(.title3)
            .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).font(.body.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .contentTransition(.opacity)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .animation(.snappy, value: state)
    }

    private var detail: String? {
        switch state {
        case .pending: nil
        case .running(let text), .done(let text), .skipped(let text), .failed(let text): text
        }
    }
}
