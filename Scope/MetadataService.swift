import Foundation

// MARK: - hexdb.io

private struct HexdbAircraftResponse: Codable {
    let iCAOTypeCode: String?
    let manufacturer: String?
    let registeredOwners: String?
    let registration: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case iCAOTypeCode = "ICAOTypeCode"
        case manufacturer = "Manufacturer"
        case registeredOwners = "RegisteredOwners"
        case registration = "Registration"
        case type = "Type"
    }
}

// MARK: - airplanes.live (fallback)

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

// MARK: - Service

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

        if let meta = await fetchHexdb(icao: icao) {
            cache[icao] = meta
            return meta
        }
        if let meta = await fetchAirplanesLive(icao: icao) {
            cache[icao] = meta
            return meta
        }
        return nil
    }

    private func fetchHexdb(icao: String) async -> AircraftMetadata? {
        guard let url = URL(string: "https://hexdb.io/api/v1/aircraft/\(icao)") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let response = try? JSONDecoder().decode(HexdbAircraftResponse.self, from: data),
              response.registration != nil || response.iCAOTypeCode != nil
        else { return nil }

        return AircraftMetadata(
            icao: icao,
            registration: response.registration,
            aircraftType: response.iCAOTypeCode,
            description: response.type,
            airline: response.registeredOwners,
            manufacturer: response.manufacturer,
            photoUrl: nil,
            fetchedAt: Date()
        )
    }

    private func fetchAirplanesLive(icao: String) async -> AircraftMetadata? {
        guard let url = URL(string: "https://api.airplanes.live/v2/icao/\(icao)") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let response = try? JSONDecoder().decode(AirplanesLiveResponse.self, from: data),
              let ac = response.ac?.first
        else { return nil }

        return AircraftMetadata(
            icao: icao,
            registration: ac.r,
            aircraftType: ac.t,
            description: ac.desc,
            airline: ac.ownOp,
            manufacturer: nil,
            photoUrl: nil,
            fetchedAt: Date()
        )
    }
}
