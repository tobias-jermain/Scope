import Foundation
import SwiftUI
import Combine

@MainActor
class AircraftViewModel: ObservableObject {
    @Published var aircraft: [Aircraft] = []
    @Published var connectionState: ConnectionState = .disconnected
    @Published var selectedAircraft: Aircraft?
    @Published var config: Config
    @Published var pollCount: Int = 0

    private var pollTask: Task<Void, Never>?
    private var beastClient: BeastStreamClient?
    private let metadataService = MetadataService()

    init() {
        self.config = Config.load()
    }

    func connect() {
        disconnect(resetState: false)
        connectionState = .connecting
        pollCount = 0
        config.save()

        switch config.dataSourceMode {
        case .beastBinary:
            connectBeast()
        case .httpJSON:
            connectHTTPJSON()
        }
    }

    func disconnect() {
        disconnect(resetState: true)
    }

    private func disconnect(resetState: Bool) {
        pollTask?.cancel()
        pollTask = nil
        beastClient?.cancel()
        beastClient = nil

        if resetState {
            connectionState = .disconnected
            aircraft = []
            selectedAircraft = nil
            pollCount = 0
        }
    }

    private func connectHTTPJSON() {
        pollTask = Task {
            while !Task.isCancelled {
                await self.pollHTTPJSON()
                do {
                    try await Task.sleep(nanoseconds: UInt64(self.config.refreshMs) * 1_000_000)
                } catch {
                    break
                }
            }
        }
    }

    private func connectBeast() {
        let client = BeastStreamClient(host: config.beastHost, port: config.beastPort)
        beastClient = client

        client.onReady = { [weak self] in
            Task { @MainActor in
                guard let self, self.beastClient === client else { return }
                self.connectionState = .connected
            }
        }

        client.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in
                guard let self, self.beastClient === client else { return }
                self.aircraft = snapshot.aircraft
                self.pollCount = snapshot.messageCount
                self.connectionState = .connected
                if let selected = self.selectedAircraft {
                    self.selectedAircraft = snapshot.aircraft.first { $0.id == selected.id }
                }
            }
        }

        client.onError = { [weak self] message in
            Task { @MainActor in
                guard let self, self.beastClient === client else { return }
                self.connectionState = .error(message)
            }
        }

        client.start()
    }

    private func pollHTTPJSON() async {
        guard let url = URL(string: "\(config.httpEndpoint)/data/aircraft.json") else {
            connectionState = .error("Invalid URL — check HTTP endpoint format")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(AircraftResponse.self, from: data)
            let valid = response.aircraft.compactMap { Aircraft(from: $0) }
            let enriched = await enrichAll(valid)

            guard !Task.isCancelled else { return }
            aircraft = enriched
            pollCount += 1
            connectionState = .connected
            if let sel = selectedAircraft, let updated = enriched.first(where: { $0.id == sel.id }) {
                selectedAircraft = updated
            }
        } catch is CancellationError {
            // silently stop
        } catch {
            guard !Task.isCancelled else { return }
            connectionState = .error(readableError(error))
        }
    }

    private func readableError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "Timed out (5s) — is dump1090 HTTP JSON running at this endpoint?"
            case .cannotConnectToHost:
                return "Cannot connect to host — check it's reachable on the network"
            case .cannotFindHost:
                return "Host not found — check the endpoint URL"
            case .networkConnectionLost:
                return "Network connection lost — retrying..."
            case .notConnectedToInternet:
                return "No network connection"
            case .appTransportSecurityRequiresSecureConnection:
                return "ATS blocked HTTP connection — disable App Sandbox or add NSAllowsArbitraryLoads"
            default:
                return urlError.localizedDescription
            }
        }
        if let decodingError = error as? DecodingError {
            return "Bad JSON from server — unexpected dump1090 format (\(decodingError.localizedDescription))"
        }
        return error.localizedDescription
    }

    private func enrichAll(_ aircraft: [Aircraft]) async -> [Aircraft] {
        let service = metadataService
        return await withTaskGroup(of: Aircraft.self) { group in
            for ac in aircraft {
                group.addTask {
                    if let meta = await service.metadata(for: ac.id) {
                        return ac.enriched(with: meta)
                    }
                    return ac
                }
            }
            var results: [Aircraft] = []
            for await ac in group { results.append(ac) }
            return results.sorted { $0.altitude > $1.altitude }
        }
    }
}
