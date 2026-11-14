import SignKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        @Bindable var model = model
        Group {
            if model.hasAccount {
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
