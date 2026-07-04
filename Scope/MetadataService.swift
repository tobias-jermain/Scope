import Foundation

private struct AirplanesLiveResponse: Codable {
    let ac: [AirplanesLiveAircraft]?
}

private struct AirplanesLiveAircraft: Codable {
    let hex: String?
    let r: String?
    let t: String?
    let desc: String?
    let ownOp: String?
}

actor MetadataService {
    private var cache: [String: AircraftMetadata] = [:]
    private var inFlight: Set<String> = []

    func metadata(for icao: String) async -> AircraftMetadata? {
        if let cached = cache[icao], !cached.isExpired {
            return cached
        }
        guard !inFlight.contains(icao) else { return cache[icao] }
        inFlight.insert(icao)
        defer { inFlight.remove(icao) }

        guard let url = URL(string: "https://api.airplanes.live/v2/icao/\(icao)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(AirplanesLiveResponse.self, from: data)
            guard let ac = response.ac?.first else { return nil }
            let metadata = AircraftMetadata(
                icao: icao,
                registration: ac.r,
                aircraftType: ac.t,
                description: ac.desc,
                airline: ac.ownOp,
                photoUrl: nil,
                fetchedAt: Date()
            )
            cache[icao] = metadata
            return metadata
        } catch {
            return nil
        }
    }
}
