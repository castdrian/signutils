import SignKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        @Bindable var model = model
        Group {
            if model.hasAccount {
                #if os(macOS)
                    MacRootView()
                        .sheet(isPresented: $model.isCreating) {
                            CreateBundleView()
                                .environment(model)
                        }
                #else
                    TabView(selection: $model.selection) {
                        Tab(SidebarItem.library.title, systemImage: SidebarItem.library.symbol, value: SidebarItem.library) {
                            LibraryView()
                        }
                        TabSection("Developer Account") {
                            Tab(SidebarItem.certificates.title, systemImage: SidebarItem.certificates.symbol, value: SidebarItem.certificates) {
                                CertificatesView()
                            }
                            Tab(SidebarItem.profiles.title, systemImage: SidebarItem.profiles.symbol, value: SidebarItem.profiles) {
                                ProfilesView()
                            }
                            Tab(SidebarItem.appIDs.title, systemImage: SidebarItem.appIDs.symbol, value: SidebarItem.appIDs) {
                                AppIDsView()
                            }
                            Tab(SidebarItem.devices.title, systemImage: SidebarItem.devices.symbol, value: SidebarItem.devices) {
                                DevicesView()
                            }
                        }
                        if sizeClass != .compact {
                            Tab(SidebarItem.settings.title, systemImage: SidebarItem.settings.symbol, value: SidebarItem.settings) {
                                SettingsView()
                            }
                        }
                    }
                    .tabViewStyle(.sidebarAdaptable)
                    .sheet(isPresented: $model.isCreating) {
                        CreateBundleView()
                            .environment(model)
                    }
                #endif
            } else {
                OnboardingView()
            }
        }
        .overlay(alignment: .bottom) { ToastView() }
        .animation(.snappy, value: model.hasAccount)
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let toast = model.toast {
            HStack(spacing: 10) {
                Image(systemName: toast.symbol)
                    .foregroundStyle(toast.isError ? .orange : .green)
                Text(toast.message)
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassBackground(in: .capsule)
            .padding(.bottom, 24)
            .padding(.horizontal, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(toast.id)
            .accessibilityIdentifier("toast")
            .onTapGesture { model.toast = nil }
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(toast.isError ? 6 : 3))
                withAnimation { if model.toast?.id == toast.id { model.toast = nil } }
            }
        }
    }
}

#if os(macOS)
    struct MacRootView: View {
        @Environment(AppModel.self) private var model

        var body: some View {
            @Bindable var model = model
            NavigationSplitView {
                List(selection: Binding<SidebarItem?>(get: { model.selection }, set: { if let value = $0 { model.selection = value } })) {
                    Label(SidebarItem.library.title, systemImage: SidebarItem.library.symbol).tag(SidebarItem.library)
                    Section("Developer Account") {
                        ForEach([SidebarItem.certificates, .profiles, .appIDs, .devices]) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                    Label(SidebarItem.settings.title, systemImage: SidebarItem.settings.symbol).tag(SidebarItem.settings)
                }
                .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            } detail: {
                switch model.selection {
                case .library: LibraryView()
                case .certificates: CertificatesView()
                case .profiles: ProfilesView()
                case .appIDs: AppIDsView()
                case .devices: DevicesView()
                case .settings: SettingsView()
                }
            }
        }
    }
#endif
