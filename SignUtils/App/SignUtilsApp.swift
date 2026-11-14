import SignKit
import SwiftUI

@main
struct SignUtilsApp: App {
    @State private var model = AppModel.launch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-screenshots") ? .dark : nil)
                .task { await model.start() }
        }
        #if os(macOS)
            .defaultSize(width: 1100, height: 760)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("New Signing Bundle…") { model.isCreating = true }
                        .keyboardShortcut("n", modifiers: [.command])
                        .disabled(!model.hasAccount)
                    Button("Refresh") { Task { await model.refresh() } }
                        .keyboardShortcut("r", modifiers: [.command])
                        .disabled(!model.hasAccount)
                }
            }
        #endif
    }
}
