import Foundation

struct AircraftMetadata: Sendable {
    let icao: String
    let registration: String?
    let aircraftType: String?
    let description: String?
    let airline: String?
    let manufacturer: String?
    let photoUrl: String?
    let fetchedAt: Date

    nonisolated var isExpired: Bool {
        Date().timeIntervalSince(fetchedAt) > 86400
    }
}
