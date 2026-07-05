import SwiftUI

struct StatusBar: View {
    @ObservedObject var viewModel: AircraftViewModel
    let onHide: () -> Void

    private var dotColor: Color {
        switch viewModel.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .secondary
        case .error: return .red
        }
    }

    private var label: String {
        switch viewModel.connectionState {
        case .connected: return "Connected · \(viewModel.config.dataSourceMode.title) · \(viewModel.config.activeEndpointDescription)"
        case .connecting: return "Connecting to \(viewModel.config.activeEndpointDescription)..."
        case .disconnected: return "Not connected"
        case .error(let m): return "Error: \(m)"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .shadow(color: dotColor.opacity(0.45), radius: 4)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if case .connected = viewModel.connectionState {
                Label("\(viewModel.aircraft.count) aircraft", systemImage: "airplane.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button(role: .destructive) {
                    viewModel.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            Button(action: onHide) {
                Image(systemName: "rectangle.bottomthird.inset.filled")
                    .imageScale(.medium)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Hide Status Bar")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

private struct WindowControlOverlay: View {
    @Binding var showSidebar: Bool
    @Binding var showStatusBar: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSidebar.toggle()
                }
            } label: {
                Image(systemName: showSidebar ? "sidebar.right" : "sidebar.right")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(showSidebar ? .primary : .secondary)
            .help(showSidebar ? "Hide Sidebar" : "Show Sidebar")

            Divider()
                .frame(height: 18)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showStatusBar.toggle()
                }
            } label: {
                Image(systemName: showStatusBar ? "rectangle.bottomthird.inset.filled" : "rectangle")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(showStatusBar ? .primary : .secondary)
            .help(showStatusBar ? "Hide Status Bar" : "Show Status Bar")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}

private struct OnboardingView: View {
    let onComplete: (ReceiverLocationMode) -> Void

    @State private var selectedLocation: ReceiverLocationMode = .remote

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(red: 0.09, green: 0.10, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Image(systemName: "scope")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)

                    Text("Set Up Scope")
                        .font(.system(.largeTitle, weight: .bold))

                    Text("Choose how Scope should receive aircraft data.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    OnboardingModeCard(
                        title: ReceiverLocationMode.local.title,
                        detail: ReceiverLocationMode.local.detail,
                        systemImage: "desktopcomputer",
                        isSelected: selectedLocation == .local,
                        isEnabled: false
                    ) {
                        selectedLocation = .local
                    }

                    OnboardingModeCard(
                        title: ReceiverLocationMode.remote.title,
                        detail: ReceiverLocationMode.remote.detail,
                        systemImage: "network",
                        isSelected: selectedLocation == .remote,
                        isEnabled: true
                    ) {
                        selectedLocation = .remote
                    }
                }
                .frame(maxWidth: 580)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Remote setup uses the current Beast Binary or HTTP JSON connection options after onboarding.", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 580, alignment: .leading)

                Button {
                    onComplete(selectedLocation)
                } label: {
                    Label("Continue", systemImage: "checkmark.circle.fill")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedLocation == .local)
            }
            .padding(32)
            .frame(width: 680)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
        }
    }
}

private struct OnboardingModeCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                    Spacer()

                    if !isEnabled {
                        Label("Soon", systemImage: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.75) : .white.opacity(0.14), lineWidth: 1.5)
            }
            .opacity(isEnabled ? 1 : 0.48)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct ContentView: View {
    @StateObject private var viewModel = AircraftViewModel()
    @AppStorage(ScopeStorageKey.showSidebar) private var showSidebar = true
    @AppStorage(ScopeStorageKey.showStatusBar) private var showStatusBar = true
    @AppStorage(ScopeStorageKey.onboardingCompleted) private var onboardingCompleted = false

    private var showConnection: Bool {
        switch viewModel.connectionState {
        case .connected: return false
        default: return true
        }
    }

    var body: some View {
        Group {
            if onboardingCompleted {
                mainInterface
            } else {
                OnboardingView { locationMode in
                    viewModel.config.receiverLocationMode = locationMode
                    viewModel.config.save()
                    withAnimation(.spring(duration: 0.28)) {
                        onboardingCompleted = true
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(minWidth: 840, minHeight: 520)
        .fontDesign(.default)
        .tint(Color(red: 0.545, green: 0.361, blue: 0.965))
        .animation(.easeInOut(duration: 0.2), value: showSidebar)
        .animation(.easeInOut(duration: 0.2), value: showStatusBar)
        .animation(.spring(duration: 0.28), value: onboardingCompleted)
    }

    private var mainInterface: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    MapView(viewModel: viewModel)
                        .ignoresSafeArea(edges: .bottom)

                    if showConnection {
                        ConnectionView(viewModel: viewModel, onboardingCompleted: onboardingCompleted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                    }

                    if let aircraft = viewModel.selectedAircraft {
                        InspectorView(aircraft: aircraft, onClose: {
                            withAnimation(.spring(duration: 0.25)) {
                                viewModel.selectedAircraft = nil
                            }
                        })
                        .padding(14)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    WindowControlOverlay(showSidebar: $showSidebar, showStatusBar: $showStatusBar)
                        .padding(14)
                }
                .animation(.easeInOut(duration: 0.2), value: showConnection)
                .animation(.spring(duration: 0.25), value: viewModel.selectedAircraft?.id)

                if showSidebar {
                    Divider()

                    SidebarView(viewModel: viewModel)
                        .frame(width: 340)
                        .background(.regularMaterial)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            if showStatusBar {
                Divider()

                StatusBar(viewModel: viewModel) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showStatusBar = false
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(.regularMaterial)
    }
}

#Preview {
    ContentView()
}
