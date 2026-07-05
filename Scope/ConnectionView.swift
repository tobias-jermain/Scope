import SwiftUI

private let scopePurple = Color(red: 0.545, green: 0.361, blue: 0.965)

struct ConnectionView: View {
    @ObservedObject var viewModel: AircraftViewModel
    let onboardingCompleted: Bool
    @State private var receiverLocationMode: ReceiverLocationMode = .remote
    @State private var dataSourceMode: DataSourceMode = .beastBinary
    @State private var beastHost: String = ""
    @State private var beastPort: String = "30002"
    @State private var httpEndpoint: String = ""
    @State private var connectingElapsed: Int = 0

    private var isConnecting: Bool { viewModel.connectionState == .connecting }

    private var canConnect: Bool {
        guard receiverLocationMode == .remote else { return false }

        switch dataSourceMode {
        case .beastBinary:
            return !beastHost.trimmingCharacters(in: .whitespaces).isEmpty && UInt16(beastPort) != nil
        case .httpJSON:
            return !httpEndpoint.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.42).ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(scopePurple)
                        .symbolRenderingMode(.hierarchical)
                    Text("Scope")
                        .font(.system(.largeTitle, weight: .bold))
                    Text("ADS-B Flight Tracker")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if isConnecting {
                    connectingBody
                } else {
                    inputBody
                }
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
        }
        .onAppear(perform: loadConfig)
        .task(id: isConnecting) {
            guard isConnecting else {
                connectingElapsed = 0
                return
            }

            connectingElapsed = 0
            while !Task.isCancelled && isConnecting {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled && isConnecting else { return }
                connectingElapsed += 1
            }
        }
    }

    // MARK: - Connecting state

    private var connectingBody: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)

            VStack(spacing: 4) {
                Text("Connecting...")
                    .font(.headline)

                Text(viewModel.config.activeEndpointDescription)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(viewModel.config.dataSourceMode.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)

                if connectingElapsed > 0 {
                    Text("\(connectingElapsed)s elapsed")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .padding(.top, 2)
                }
            }

            if connectingElapsed >= 3 {
                VStack(spacing: 4) {
                    Text(connectingDetailText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fontDesign(.monospaced)

                    if connectingElapsed >= 6 {
                        Text(longConnectText)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                    }
                }
                .transition(.opacity)
            }

            Button("Cancel") {
                viewModel.disconnect()
            }
            .buttonStyle(.glass)
        }
        .animation(.easeInOut, value: connectingElapsed)
    }

    private var connectingDetailText: String {
        switch viewModel.config.dataSourceMode {
        case .beastBinary:
            return "Opening Beast TCP stream on port \(viewModel.config.beastPort)"
        case .httpJSON:
            return "Polling /data/aircraft.json"
        }
    }

    private var longConnectText: String {
        switch viewModel.config.dataSourceMode {
        case .beastBinary:
            return "Check that dump1090 is listening on \(viewModel.config.beastHost):\(viewModel.config.beastPort)"
        case .httpJSON:
            return "Taking longer than expected - HTTP timeout is 5s per attempt"
        }
    }

    // MARK: - Input form

    private var inputBody: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connection")
                    .font(.headline)

                connectionLocationPicker

                if receiverLocationMode == .remote {
                    remoteSourceControls
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: receiverLocationMode)

            Button("Connect", action: attemptConnect)
                .buttonStyle(.borderedProminent)
                .tint(scopePurple)
                .disabled(!canConnect)
                .frame(width: 160)

            if case .error(let msg) = viewModel.connectionState {
                VStack(spacing: 6) {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)

                    Text(errorHelpText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, -4)
            }
        }
    }

    private var connectionLocationPicker: some View {
        HStack(spacing: 8) {
            connectionLocationButton(
                mode: .local,
                systemImage: "desktopcomputer",
                isEnabled: false
            )

            connectionLocationButton(
                mode: .remote,
                systemImage: "network",
                isEnabled: true
            )
        }
        .frame(width: 360)
    }

    private func connectionLocationButton(
        mode: ReceiverLocationMode,
        systemImage: String,
        isEnabled: Bool
    ) -> some View {
        Button {
            receiverLocationMode = mode
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(mode.title)
                    .fontWeight(.medium)
                Spacer(minLength: 0)
                if !isEnabled {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                }
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(locationBackground(for: mode), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(receiverLocationMode == mode ? scopePurple.opacity(0.8) : .white.opacity(0.14), lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(isEnabled ? mode.detail : "Local receiver support is coming later")
    }

    private func locationBackground(for mode: ReceiverLocationMode) -> Color {
        receiverLocationMode == mode ? scopePurple.opacity(0.16) : Color.secondary.opacity(0.08)
    }

    private var remoteSourceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: $dataSourceMode) {
                ForEach(DataSourceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 360)
            .help("Choose Remote Receiver Protocol")

            Text(dataSourceMode.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 360, alignment: .leading)

            sourceFields
        }
    }

    @ViewBuilder
    private var sourceFields: some View {
        switch dataSourceMode {
        case .beastBinary:
            HStack(spacing: 8) {
                TextField("192.168.1.146", text: $beastHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 238)
                    .onSubmit { attemptConnect() }

                TextField("30002", text: $beastPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 114)
                    .onSubmit { attemptConnect() }
            }
        case .httpJSON:
            TextField("http://192.168.1.146:8080", text: $httpEndpoint)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)
                .onSubmit { attemptConnect() }
        }
    }

    private var errorHelpText: String {
        switch dataSourceMode {
        case .beastBinary:
            return "Check: is dump1090 running and exposing Beast output on port 30002?"
        case .httpJSON:
            return "Check: is the web server enabled and serving /data/aircraft.json?"
        }
    }

    private func loadConfig() {
        receiverLocationMode = viewModel.config.receiverLocationMode
        dataSourceMode = viewModel.config.dataSourceMode
        beastHost = viewModel.config.beastHost
        beastPort = String(viewModel.config.beastPort)
        httpEndpoint = viewModel.config.httpEndpoint
    }

    private func attemptConnect() {
        guard canConnect else { return }
        viewModel.config.receiverLocationMode = receiverLocationMode
        viewModel.config.dataSourceMode = dataSourceMode

        switch dataSourceMode {
        case .beastBinary:
            viewModel.config.beastHost = beastHost.trimmingCharacters(in: .whitespaces)
            viewModel.config.beastPort = UInt16(beastPort) ?? 30002
        case .httpJSON:
            let trimmed = httpEndpoint.trimmingCharacters(in: .whitespaces)
            viewModel.config.httpEndpoint = trimmed
            viewModel.config.endpoint = trimmed
        }

        viewModel.connect()
    }
}
