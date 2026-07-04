import SwiftUI

struct StatusBar: View {
    @ObservedObject var viewModel: AircraftViewModel

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
        HStack(spacing: 8) {
            Circle().fill(dotColor).frame(width: 6, height: 6)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if case .connected = viewModel.connectionState {
                Text("\(viewModel.aircraft.count) aircraft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button("Disconnect") { viewModel.disconnect() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct ContentView: View {
    @StateObject private var viewModel = AircraftViewModel()

    private var showConnection: Bool {
        switch viewModel.connectionState {
        case .connected: return false
        default: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    MapView(viewModel: viewModel)

                    if showConnection {
                        ConnectionView(viewModel: viewModel)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                    }

                    if let aircraft = viewModel.selectedAircraft {
                        InspectorView(aircraft: aircraft, onClose: {
                            withAnimation(.spring(duration: 0.25)) {
                                viewModel.selectedAircraft = nil
                            }
                        })
                        .padding(12)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showConnection)
                .animation(.spring(duration: 0.25), value: viewModel.selectedAircraft?.id)

                Divider()

                SidebarView(viewModel: viewModel)
                    .frame(width: 340)
            }

            Divider()

            StatusBar(viewModel: viewModel)
        }
        .frame(minWidth: 840, minHeight: 520)
    }
}

#Preview {
    ContentView()
}
