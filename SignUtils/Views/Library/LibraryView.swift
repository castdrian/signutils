import SignKit
import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var showsSettings = false

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case inactive = "Expired or revoked"
        var id: String { rawValue }
    }

    private var visible: [LibraryEntry] {
        model.entries.filter { entry in
            let status = entry.effectiveStatus()
            let matchesFilter =
                switch filter {
                case .all: true
                case .active: status == .active
                case .inactive: status != .active
                }
            let matchesSearch =
                search.isEmpty || entry.bundle.name.localizedCaseInsensitiveContains(search)
                || entry.bundle.bundleIdentifier.localizedCaseInsensitiveContains(search)
            return matchesFilter && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    DemoBanner()
                    if !model.entries.isEmpty {
                        Section {
                            Picker("Show", selection: $filter) {
                                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                        }
                    }
                    ForEach(visible) { entry in
                        NavigationLink(value: entry.id) {
                            LibraryRow(entry: entry)
                        }
                        .contextMenu {
                            if let url = model.archiveURL(for: entry) {
                                ShareLink(item: url) { Label("Share Archive", systemImage: "square.and.arrow.up") }
                            }
                            Button {
                                Clipboard.copy(entry.bundle.password)
                                model.toast = Toast("Password copied", symbol: "doc.on.doc.fill")
                            } label: {
                                Label("Copy Password", systemImage: "key")
                            }
                            Divider()
                            Button(role: .destructive) {
                                model.removeFromLibrary(entry)
                            } label: {
                                Label("Remove from Library", systemImage: "trash")
                            }
                        }
                    }
                }
                .overlay {
                    if model.entries.isEmpty {
                        ContentUnavailableView {
                            Label("No signing bundles yet", systemImage: "doc.zipper")
                        } description: {
                            Text("Create your first bundle to get a zip with a .p12, its password and a provisioning profile.")
                        } actions: {
                            Button {
                                model.isCreating = true
                            } label: {
                                Label("New Signing Bundle", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("emptyCreate")
                        }
                    } else if visible.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: UUID.self) { id in
                if let entry = model.entries.first(where: { $0.id == id }) {
                    LibraryDetailView(entry: entry)
                }
            }
            .searchable(text: $search, prompt: "Search bundles")
            .refreshable { await model.refresh() }
            .sheet(isPresented: $showsSettings) {
                SettingsView().environment(model)
            }
            .toolbar {
                if sizeClass == .compact {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            showsSettings = true
                        } label: {
                            Label("Settings", systemImage: "person.crop.circle")
                        }
                        .accessibilityIdentifier("settings")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.isCreating = true
                    } label: {
                        Label("New Signing Bundle", systemImage: "plus")
                    }
                    .accessibilityIdentifier("newBundle")
                }
            }
        }
    }
}

struct LibraryRow: View {
    var entry: LibraryEntry

    var body: some View {
        let status = entry.effectiveStatus()
        HStack(spacing: 14) {
            IconBadge(
                symbol: entry.bundle.kind == .development ? "hammer.fill" : "shippingbox.fill",
                color: status == .active ? (entry.bundle.kind == .development ? .blue : .purple) : .gray,
                size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.bundle.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    StatusPill(status: status)
                }
                Text(entry.bundle.bundleIdentifier)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Label("\(entry.bundle.devices.count)", systemImage: "iphone")
                    Label("\(entry.bundle.capabilities.count)", systemImage: "switch.2")
                    ExpiryText(date: entry.bundle.expiration)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("libraryRow")
    }
}
