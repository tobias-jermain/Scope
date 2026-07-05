import SwiftUI

struct ScopeStorageKey {
    static let showSidebar = "showSidebar"
    static let showStatusBar = "showStatusBar"
    static let onboardingCompleted = "onboardingCompleted"
}

struct ScopeSettingsView: View {
    @AppStorage(ScopeStorageKey.showSidebar) private var showSidebar = true
    @AppStorage(ScopeStorageKey.showStatusBar) private var showStatusBar = true
    @AppStorage(ScopeStorageKey.onboardingCompleted) private var onboardingCompleted = false

    var body: some View {
        Form {
            Section("Interface") {
                Toggle("Show sidebar", isOn: $showSidebar)
                Toggle("Show status bar", isOn: $showStatusBar)
                Toggle("Onboarding complete", isOn: $onboardingCompleted)
            }

            Section("Setup") {
                Button("Show onboarding again") {
                    onboardingCompleted = false
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }
}

struct ScopeCommands: Commands {
    @AppStorage(ScopeStorageKey.showSidebar) private var showSidebar = true
    @AppStorage(ScopeStorageKey.showStatusBar) private var showStatusBar = true
    @AppStorage(ScopeStorageKey.onboardingCompleted) private var onboardingCompleted = false

    var body: some Commands {
        CommandMenu("Scope") {
            Toggle("Show Sidebar", isOn: $showSidebar)
                .keyboardShortcut("s", modifiers: [.command, .shift])

            Toggle("Show Status Bar", isOn: $showStatusBar)
                .keyboardShortcut("s", modifiers: [.command, .option])

            Divider()

            Button("Show Onboarding Again") {
                onboardingCompleted = false
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
        }
    }
}
