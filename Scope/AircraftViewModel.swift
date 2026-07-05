import CoreLocation
import Foundation
import SwiftUI
import Combine

// MARK: - Location service

private final class LocationService: NSObject, CLLocationManagerDelegate {
    var onLocation: ((CLLocationCoordinate2D) -> Void)?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        onLocation?(loc.coordinate)
        // One update is enough — stop to avoid unnecessary battery use
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - View model

@MainActor
class AircraftViewModel: ObservableObject {
    @Published var aircraft: [Aircraft] = []
    @Published var connectionState: ConnectionState = .disconnected
    @Published var selectedAircraft: Aircraft?
    @Published var config: Config
    @Published var pollCount: Int = 0
    @Published var userLocation: CLLocationCoordinate2D?

    private var pollTask: Task<Void, Never>?
    private var beastClient: BeastStreamClient?
    private let metadataService = MetadataService()
    private let locationService = LocationService()

    // Throttle Beast snapshot updates to avoid rapid redraws causing flicker
    private var lastAircraftUpdate: Date = .distantPast

    init() {
        self.config = Config.load()
        locationService.onLocation = { [weak self] coord in
            Task { @MainActor in
                self?.userLocation = coord
            }
        }
    }

    func startLocationUpdates() {
        locationService.start()
    }

    func connect() {
        disconnect(resetState: false)

        guard config.receiverLocationMode == .remote else {
            connectionState = .error("Local receiver mode is not available yet")
            return
        }

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
                self.pollCount = snapshot.messageCount
                self.connectionState = .connected

                // Throttle UI updates to ~10 fps — Beast emits far more frequently
                let now = Date()
                guard now.timeIntervalSince(self.lastAircraftUpdate) >= 0.1 else { return }
                self.lastAircraftUpdate = now

                let enriched = await self.enrichAll(snapshot.aircraft)
                guard !Task.isCancelled, self.beastClient === client else { return }
                self.aircraft = enriched
                if let selected = self.selectedAircraft {
                    self.selectedAircraft = enriched.first { $0.id == selected.id }
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
