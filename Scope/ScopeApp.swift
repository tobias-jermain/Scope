import SwiftUI

@main
struct ScopeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1400, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .help) {}
            CommandGroup(replacing: .appInfo) {
                Button("About Scope") {}
            }
        }
    }
}
