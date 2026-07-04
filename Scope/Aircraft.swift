import Foundation
import CoreLocation

enum AltitudeValue: Codable {
    case feet(Int)
    case ground

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let feet = try? container.decode(Int.self) {
            self = .feet(feet)
        } else {
            self = .ground
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .feet(let v): try container.encode(v)
        case .ground: try container.encode("ground")
        }
    }

    var feet: Int {
        switch self {
        case .feet(let v): return v
        case .ground: return 0
        }
    }
}

struct AircraftResponse: Codable {
    let now: Double?
    let messages: Int?
    let aircraft: [AircraftJSON]
}

struct AircraftJSON: Codable {
    let hex: String
    let flight: String?
    let r: String?
    let t: String?
    let lat: Double?
    let lon: Double?
    let altBaro: AltitudeValue?
    let gs: Double?
    let track: Double?
    let baroRate: Int?
    let squawk: String?
    let category: String?
    let seen: Double?

    enum CodingKeys: String, CodingKey {
        case hex, flight, r, t, lat, lon, squawk, category, seen
        case altBaro = "alt_baro"
        case gs, track
        case baroRate = "baro_rate"
    }
}

struct Aircraft: Identifiable, Equatable, Hashable {
    let id: String
    let callsign: String?
    let position: CLLocationCoordinate2D
    let altitude: Int
    let speed: Int
    let track: Double
    let verticalRate: Int
    let squawk: String?
    let category: String?
    let registration: String?
    let aircraftType: String?
    let airline: String?
    let photoUrl: String?
    let lastSeen: Date

    static func == (lhs: Aircraft, rhs: Aircraft) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init?(from json: AircraftJSON) {
        guard let lat = json.lat, let lon = json.lon else { return nil }
        self.id = json.hex.lowercased()
        self.callsign = json.flight?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        self.position = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        self.altitude = json.altBaro?.feet ?? 0
        self.speed = Int(json.gs ?? 0)
        self.track = json.track ?? 0
        self.verticalRate = json.baroRate ?? 0
        self.squawk = json.squawk
        self.category = json.category
        self.registration = json.r
        self.aircraftType = json.t
        self.airline = nil
        self.photoUrl = nil
        self.lastSeen = Date()
    }

    nonisolated func enriched(with metadata: AircraftMetadata) -> Aircraft {
        Aircraft(
            id: id,
            callsign: callsign,
            position: position,
            altitude: altitude,
            speed: speed,
            track: track,
            verticalRate: verticalRate,
            squawk: squawk,
            category: category,
            registration: metadata.registration ?? registration,
            aircraftType: metadata.aircraftType ?? aircraftType,
            airline: metadata.airline ?? airline,
            photoUrl: metadata.photoUrl ?? photoUrl,
            lastSeen: lastSeen
        )
    }

    init(id: String, callsign: String?, position: CLLocationCoordinate2D,
         altitude: Int, speed: Int, track: Double, verticalRate: Int,
         squawk: String?, category: String?, registration: String?,
         aircraftType: String?, airline: String?, photoUrl: String?, lastSeen: Date) {
        self.id = id
        self.callsign = callsign
        self.position = position
        self.altitude = altitude
        self.speed = speed
        self.track = track
        self.verticalRate = verticalRate
        self.squawk = squawk
        self.category = category
        self.registration = registration
        self.aircraftType = aircraftType
        self.airline = airline
        self.photoUrl = photoUrl
        self.lastSeen = lastSeen
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}
