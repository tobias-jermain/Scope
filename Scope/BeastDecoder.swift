import CoreLocation
import Foundation

struct BeastSnapshot {
    let aircraft: [Aircraft]
    let messageCount: Int
}

final class BeastDecoder {
    private enum FrameState {
        case seekingStart
        case readingType
        case readingPayload(type: UInt8, expectedLength: Int, bytes: [UInt8])
    }

    private struct TrackedAircraft {
        var id: String
        var callsign: String?
        var position: CLLocationCoordinate2D?
        var altitude: Int
        var speed: Int
        var track: Double
        var verticalRate: Int
        var squawk: String?
        var category: String?
        var registration: String?
        var aircraftType: String?
        var airline: String?
        var photoUrl: String?
        var lastSeen: Date
        var evenCPR: CPRFrame?
        var oddCPR: CPRFrame?

        var aircraft: Aircraft? {
            guard let position else { return nil }
            return Aircraft(
                id: id,
                callsign: callsign,
                position: position,
                altitude: altitude,
                speed: speed,
                track: track,
                verticalRate: verticalRate,
                squawk: squawk,
                category: category,
                registration: registration,
                aircraftType: aircraftType,
                airline: airline,
                photoUrl: photoUrl,
                lastSeen: lastSeen
            )
        }
    }

    private struct CPRFrame {
        let latitude: Int
        let longitude: Int
        let isOdd: Bool
        let altitude: Int
        let timestamp: Date
    }

    private var state: FrameState = .seekingStart
    private var escaped = false
    private var tracked: [String: TrackedAircraft] = [:]
    private var messageCount = 0

    func ingest(_ data: Data) -> BeastSnapshot? {
        var changed = false
        for byte in data {
            if process(byte) { changed = true }
        }

        pruneExpired()
        guard changed else { return nil }
        return BeastSnapshot(
            aircraft: tracked.values.compactMap(\.aircraft).sorted { $0.altitude > $1.altitude },
            messageCount: messageCount
        )
    }

    private func process(_ byte: UInt8) -> Bool {
        if escaped {
            escaped = false
            return consume(byte)
        }

        if byte == 0x1A {
            switch state {
            case .seekingStart:
                state = .readingType
            default:
                escaped = true
            }
            return false
        }

        return consume(byte)
    }

    private func consume(_ byte: UInt8) -> Bool {
        switch state {
        case .seekingStart:
            return false
        case .readingType:
            guard let expectedLength = payloadLength(for: byte) else {
                state = .seekingStart
                return false
            }
            state = .readingPayload(type: byte, expectedLength: expectedLength, bytes: [])
            return false
        case .readingPayload(let type, let expectedLength, var bytes):
            bytes.append(byte)
            if bytes.count == expectedLength {
                state = .seekingStart
                return handleFrame(type: type, payload: bytes)
            }
            state = .readingPayload(type: type, expectedLength: expectedLength, bytes: bytes)
            return false
        }
    }

    private func payloadLength(for type: UInt8) -> Int? {
        switch Character(UnicodeScalar(type)) {
        case "1": return 9
        case "2": return 14
        case "3": return 21
        default: return nil
        }
    }

    private func handleFrame(type: UInt8, payload: [UInt8]) -> Bool {
        let modeS: ArraySlice<UInt8>
        switch Character(UnicodeScalar(type)) {
        case "2": modeS = payload.suffix(7)
        case "3": modeS = payload.suffix(14)
        default: return false
        }
        return decodeModeS(Array(modeS))
    }

    private func decodeModeS(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 14 else { return false }
        let downlinkFormat = bytes[0] >> 3
        guard downlinkFormat == 17 || downlinkFormat == 18 else { return false }

        let icao = String(format: "%02x%02x%02x", bytes[1], bytes[2], bytes[3])
        let typeCode = bytes[4] >> 3
        var current = tracked[icao] ?? TrackedAircraft(
            id: icao,
            callsign: nil,
            position: nil,
            altitude: 0,
            speed: 0,
            track: 0,
            verticalRate: 0,
            squawk: nil,
            category: nil,
            registration: nil,
            aircraftType: nil,
            airline: nil,
            photoUrl: nil,
            lastSeen: Date(),
            evenCPR: nil,
            oddCPR: nil
        )

        current.lastSeen = Date()
        var changed = false

        switch typeCode {
        case 1...4:
            if let callsign = decodeCallsign(bytes) {
                current.callsign = callsign
                changed = true
            }
        case 9...18:
            if let frame = decodeAirbornePosition(bytes) {
                current.altitude = frame.altitude
                if frame.isOdd {
                    current.oddCPR = frame
                } else {
                    current.evenCPR = frame
                }
                if let position = resolveGlobalCPR(even: current.evenCPR, odd: current.oddCPR) {
                    current.position = position
                    changed = true
                }
            }
        case 19:
            if decodeVelocity(bytes, into: &current) {
                changed = true
            }
        default:
            break
        }

        tracked[icao] = current
        messageCount += 1
        return changed
    }

    private func decodeCallsign(_ bytes: [UInt8]) -> String? {
        let charset = Array("#ABCDEFGHIJKLMNOPQRSTUVWXYZ#####_###############0123456789######")
        let bits = bits(from: bytes[5...10])
        var characters: [Character] = []
        for offset in stride(from: 0, to: 48, by: 6) {
            let index = Int(bitValue(bits, offset: offset, length: 6))
            guard charset.indices.contains(index) else { continue }
            let char = charset[index]
            if char != "#" && char != "_" { characters.append(char) }
        }
        let callsign = String(characters).trimmingCharacters(in: .whitespaces)
        return callsign.nilIfEmpty
    }

    private func decodeAirbornePosition(_ bytes: [UInt8]) -> CPRFrame? {
        let altitudeCode = (UInt16(bytes[5] & 0xFE) << 4) | UInt16((bytes[6] & 0xF0) >> 4)
        let altitude = decodeAltitude(altitudeCode)
        let isOdd = (bytes[6] & 0x04) != 0
        let encodedLatitude = (Int(bytes[6] & 0x03) << 15) | (Int(bytes[7]) << 7) | Int(bytes[8] >> 1)
        let encodedLongitude = (Int(bytes[8] & 0x01) << 16) | (Int(bytes[9]) << 8) | Int(bytes[10])

        return CPRFrame(
            latitude: encodedLatitude,
            longitude: encodedLongitude,
            isOdd: isOdd,
            altitude: altitude,
            timestamp: Date()
        )
    }

    private func decodeAltitude(_ code: UInt16) -> Int {
        let qBit = (code & 0x10) != 0
        guard qBit else { return 0 }
        let n = Int((code & 0x0F) | ((code & 0xFE0) >> 1))
        return n * 25 - 1000
    }

    private func decodeVelocity(_ bytes: [UInt8], into aircraft: inout TrackedAircraft) -> Bool {
        let bits = bits(from: bytes[4...10])
        let subtype = Int(bitValue(bits, offset: 5, length: 3))
        guard subtype == 1 || subtype == 2 else { return false }

        let ewDirection = bitValue(bits, offset: 13, length: 1) == 1
        let ewVelocity = Int(bitValue(bits, offset: 14, length: 10)) - 1
        let nsDirection = bitValue(bits, offset: 24, length: 1) == 1
        let nsVelocity = Int(bitValue(bits, offset: 25, length: 10)) - 1
        guard ewVelocity >= 0, nsVelocity >= 0 else { return false }

        let east = Double(ewDirection ? -ewVelocity : ewVelocity)
        let north = Double(nsDirection ? -nsVelocity : nsVelocity)
        aircraft.speed = Int(hypot(east, north).rounded())
        aircraft.track = fmod(atan2(east, north) * 180 / .pi + 360, 360)

        let verticalRateSign = bitValue(bits, offset: 36, length: 1) == 1
        let verticalRateValue = Int(bitValue(bits, offset: 37, length: 9)) - 1
        if verticalRateValue >= 0 {
            aircraft.verticalRate = (verticalRateSign ? -1 : 1) * verticalRateValue * 64
        }
        return true
    }

    private func resolveGlobalCPR(even: CPRFrame?, odd: CPRFrame?) -> CLLocationCoordinate2D? {
        guard let even, let odd else { return nil }
        guard abs(even.timestamp.timeIntervalSince(odd.timestamp)) <= 10 else { return nil }

        let evenLat = Double(even.latitude) / 131072.0
        let oddLat = Double(odd.latitude) / 131072.0
        let j = floor(59.0 * evenLat - 60.0 * oddLat + 0.5)
        var latitudeEven = 6.0 * (mod(j, 60.0) + evenLat)
        var latitudeOdd = 360.0 / 59.0 * (mod(j, 59.0) + oddLat)

        if latitudeEven >= 270 { latitudeEven -= 360 }
        if latitudeOdd >= 270 { latitudeOdd -= 360 }
        guard cprNL(latitudeEven) == cprNL(latitudeOdd) else { return nil }

        let useEven = even.timestamp > odd.timestamp
        let latitude = useEven ? latitudeEven : latitudeOdd
        let ni = max(useEven ? cprNL(latitude) : cprNL(latitude) - 1, 1)
        let longitudeZone = Double(ni)
        let m = floor(
            (Double(even.longitude) * (Double(cprNL(latitude)) - 1) - Double(odd.longitude) * Double(cprNL(latitude))) / 131072.0 + 0.5
        )
        let longitude = 360.0 / longitudeZone * (mod(m, longitudeZone) + Double(useEven ? even.longitude : odd.longitude) / 131072.0)
        let normalizedLongitude = longitude > 180 ? longitude - 360 : longitude

        return CLLocationCoordinate2D(latitude: latitude, longitude: normalizedLongitude)
    }

    private func cprNL(_ latitude: Double) -> Int {
        let lat = abs(latitude)
        switch lat {
        case 0..<10.47047130: return 59
        case 10.47047130..<14.82817437: return 58
        case 14.82817437..<18.18626357: return 57
        case 18.18626357..<21.02939493: return 56
        case 21.02939493..<23.54504487: return 55
        case 23.54504487..<25.82924707: return 54
        case 25.82924707..<27.93898710: return 53
        case 27.93898710..<29.91135686: return 52
        case 29.91135686..<31.77209708: return 51
        case 31.77209708..<33.53993436: return 50
        case 33.53993436..<35.22899598: return 49
        case 35.22899598..<36.85025108: return 48
        case 36.85025108..<38.41241892: return 47
        case 38.41241892..<39.92256684: return 46
        case 39.92256684..<41.38651832: return 45
        case 41.38651832..<42.80914012: return 44
        case 42.80914012..<44.19454951: return 43
        case 44.19454951..<45.54626723: return 42
        case 45.54626723..<46.86733252: return 41
        case 46.86733252..<48.16039128: return 40
        case 48.16039128..<49.42776439: return 39
        case 49.42776439..<50.67150166: return 38
        case 50.67150166..<51.89342469: return 37
        case 51.89342469..<53.09516153: return 36
        case 53.09516153..<54.27817472: return 35
        case 54.27817472..<55.44378444: return 34
        case 55.44378444..<56.59318756: return 33
        case 56.59318756..<57.72747354: return 32
        case 57.72747354..<58.84763776: return 31
        case 58.84763776..<59.95459277: return 30
        case 59.95459277..<61.04917774: return 29
        case 61.04917774..<62.13216659: return 28
        case 62.13216659..<63.20427479: return 27
        case 63.20427479..<64.26616523: return 26
        case 64.26616523..<65.31845310: return 25
        case 65.31845310..<66.36171008: return 24
        case 66.36171008..<67.39646774: return 23
        case 67.39646774..<68.42322022: return 22
        case 68.42322022..<69.44242631: return 21
        case 69.44242631..<70.45451075: return 20
        case 70.45451075..<71.45986473: return 19
        case 71.45986473..<72.45884545: return 18
        case 72.45884545..<73.45177442: return 17
        case 73.45177442..<74.43893416: return 16
        case 74.43893416..<75.42056257: return 15
        case 75.42056257..<76.39684391: return 14
        case 76.39684391..<77.36789461: return 13
        case 77.36789461..<78.33374083: return 12
        case 78.33374083..<79.29428225: return 11
        case 79.29428225..<80.24923213: return 10
        case 80.24923213..<81.19801349: return 9
        case 81.19801349..<82.13956981: return 8
        case 82.13956981..<83.07199445: return 7
        case 83.07199445..<83.99173563: return 6
        case 83.99173563..<84.89166191: return 5
        case 84.89166191..<85.75541621: return 4
        case 85.75541621..<86.53536998: return 3
        case 86.53536998..<87.00000000: return 2
        default: return 1
        }
    }

    private func bits(from bytes: ArraySlice<UInt8>) -> [UInt8] {
        bytes.flatMap { byte in (0..<8).map { UInt8((byte >> (7 - $0)) & 1) } }
    }

    private func bitValue(_ bits: [UInt8], offset: Int, length: Int) -> UInt64 {
        guard length > 0, offset >= 0, offset + length <= bits.count else { return 0 }
        return bits[offset..<(offset + length)].reduce(UInt64(0)) { ($0 << 1) | UInt64($1) }
    }

    private func mod(_ value: Double, _ divisor: Double) -> Double {
        value - divisor * floor(value / divisor)
    }

    private func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-30)
        tracked = tracked.filter { $0.value.lastSeen >= cutoff }
    }
}
