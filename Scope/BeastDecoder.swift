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
        var evenSurfaceCPR: CPRFrame?
        var oddSurfaceCPR: CPRFrame?

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
        case "1": return 9   // 6-byte MLAT + 1-byte signal + 2-byte Mode-AC
        case "2": return 14  // 6-byte MLAT + 1-byte signal + 7-byte Mode-S short
        case "3": return 21  // 6-byte MLAT + 1-byte signal + 14-byte Mode-S long
        default: return nil
        }
    }

    private func handleFrame(type: UInt8, payload: [UInt8]) -> Bool {
        switch Character(UnicodeScalar(type)) {
        case "2":
            return decodeModeS7(Array(payload.suffix(7)))
        case "3":
            return decodeModeS(Array(payload.suffix(14)))
        default:
            return false
        }
    }

    // MARK: - 7-byte Mode S short frames (Beast type "2")

    private func decodeModeS7(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 7 else { return false }
        let df = bytes[0] >> 3
        // DF5: Surveillance Identity Reply — contains Mode A squawk
        guard df == 5 else { return false }

        // Recover ICAO via CRC: AP = ICAO XOR CRC(data), so ICAO = CRC(data) XOR AP
        let computedCRC = modesCRC(Array(bytes[0...3]))
        let ap = (UInt32(bytes[4]) << 16) | (UInt32(bytes[5]) << 8) | UInt32(bytes[6])
        let icao = String(format: "%06x", computedCRC ^ ap)

        // Only update aircraft already seen via ADS-B; avoids CRC false-positives
        guard tracked[icao] != nil else { return false }

        // Identity is in the upper 13 bits of bytes[2..3]
        let identBits = (UInt16(bytes[2]) << 5) | UInt16(bytes[3] >> 3)
        let squawk = decodeSquawk(identBits)
        guard squawk != "0000" else { return false }

        var current = tracked[icao]!
        current.squawk = squawk
        current.lastSeen = Date()
        tracked[icao] = current
        return true
    }

    // Mode S CRC-24 using polynomial 0xFFF409
    private func modesCRC(_ bytes: [UInt8]) -> UInt32 {
        let poly: UInt32 = 0xFFF409
        var crc: UInt32 = 0
        for byte in bytes {
            crc ^= UInt32(byte) << 16
            for _ in 0..<8 {
                crc <<= 1
                if crc & 0x1000000 != 0 { crc ^= poly }
            }
        }
        return crc & 0xFFFFFF
    }

    // MARK: - 14-byte Mode S long frames (Beast type "3")

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
            oddCPR: nil,
            evenSurfaceCPR: nil,
            oddSurfaceCPR: nil
        )

        current.lastSeen = Date()
        var changed = false

        switch typeCode {
        case 1...4:
            // Aircraft identification: callsign + wake turbulence category (A1–D7)
            let categoryLetter = ["D", "C", "B", "A"][Int(typeCode) - 1]
            let categoryDigit = Int(bytes[4] & 0x07)
            if categoryDigit != 0 {
                current.category = "\(categoryLetter)\(categoryDigit)"
                changed = true
            }
            if let callsign = decodeCallsign(bytes) {
                current.callsign = callsign
                changed = true
            }

        case 5...8:
            // Surface position (aircraft taxiing on ground)
            let (frame, track) = decodeSurfacePosition(bytes)
            if frame.isOdd {
                current.oddSurfaceCPR = frame
            } else {
                current.evenSurfaceCPR = frame
            }
            if let position = resolveGlobalSurfaceCPR(even: current.evenSurfaceCPR, odd: current.oddSurfaceCPR) {
                current.position = position
                current.altitude = 0
                if let t = track { current.track = t }
                changed = true
            }

        case 9...18:
            // Airborne position with barometric altitude
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
            // Airborne velocity (ground speed or airspeed + heading)
            if decodeVelocity(bytes, into: &current) {
                changed = true
            }

        case 20...22:
            // Airborne position with GNSS altitude — same CPR encoding as TC 9-18
            if let frame = decodeAirbornePosition(bytes) {
                if frame.altitude != 0 { current.altitude = frame.altitude }
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

        case 28:
            // Aircraft status — emergency state + embedded Mode A squawk
            if let squawk = decodeAircraftStatus(bytes) {
                current.squawk = squawk
                changed = true
            }

        default:
            break
        }

        tracked[icao] = current
        messageCount += 1
        return changed
    }

    // MARK: - Message decoders

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

    private func decodeSurfacePosition(_ bytes: [UInt8]) -> (CPRFrame, Double?) {
        // ME bits: 0-4 TC | 5-11 MOV | 12 status | 13-19 track | 20 T | 21 F | 22-38 lat | 39-55 lon
        let bits = bits(from: bytes[4...10])
        let status = bitValue(bits, offset: 12, length: 1)
        let track: Double? = status != 0
            ? Double(bitValue(bits, offset: 13, length: 7)) * (360.0 / 128.0)
            : nil
        let isOdd = bitValue(bits, offset: 21, length: 1) != 0
        let encodedLat = Int(bitValue(bits, offset: 22, length: 17))
        let encodedLon = Int(bitValue(bits, offset: 39, length: 17))
        let frame = CPRFrame(latitude: encodedLat, longitude: encodedLon, isOdd: isOdd, altitude: 0, timestamp: Date())
        return (frame, track)
    }

    private func decodeAirbornePosition(_ bytes: [UInt8]) -> CPRFrame? {
        // Altitude: bytes[5] = alt bits 1-8, bytes[6] upper nibble = alt bits 9-12
        // Q bit is bit 4 of the resulting 12-bit code (alt bit 8 of bytes[5])
        let altitudeCode = (UInt16(bytes[5]) << 4) | UInt16(bytes[6] >> 4)
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
        // Q bit at position 4 (value 0x10) indicates 25ft-resolution encoding
        let qBit = (code & 0x10) != 0
        guard qBit else { return 0 }
        let n = Int((code & 0x0F) | ((code & 0xFE0) >> 1))
        return n * 25 - 1000
    }

    private func decodeAircraftStatus(_ bytes: [UInt8]) -> String? {
        // ME bits: 0-4 TC | 5-7 subtype | 8-10 emergency | 11-23 Mode A code (13 bits)
        let bits = bits(from: bytes[4...10])
        let subtype = Int(bitValue(bits, offset: 5, length: 3))
        guard subtype == 1 else { return nil }
        let code = UInt16(bitValue(bits, offset: 11, length: 13))
        let squawk = decodeSquawk(code)
        return squawk == "0000" ? nil : squawk
    }

    // Convert 13-bit Mode A identity code (C1 A1 C2 B1 D2 B2 D4 A4 C4 A2 B4 D1 SPI)
    // to a 4-digit squawk string (e.g. "7700").
    private func decodeSquawk(_ code: UInt16) -> String {
        let bit: (Int) -> Int = { Int((code >> (12 - $0)) & 1) }
        let a = (bit(7) << 2) | (bit(9) << 1) | bit(1)  // A4 A2 A1
        let b = (bit(10) << 2) | (bit(5) << 1) | bit(3) // B4 B2 B1
        let c = (bit(8) << 2) | (bit(2) << 1) | bit(0)  // C4 C2 C1
        let d = (bit(6) << 2) | (bit(4) << 1) | bit(11) // D4 D2 D1
        return String(format: "%d%d%d%d", a, b, c, d)
    }

    private func decodeVelocity(_ bytes: [UInt8], into aircraft: inout TrackedAircraft) -> Bool {
        let bits = bits(from: bytes[4...10])
        let subtype = Int(bitValue(bits, offset: 5, length: 3))

        switch subtype {
        case 1, 2:
            // Ground speed: separate EW and NS velocity components
            let ewDirection = bitValue(bits, offset: 13, length: 1) == 1 // 1 = West
            let ewVelocity = Int(bitValue(bits, offset: 14, length: 10)) - 1
            let nsDirection = bitValue(bits, offset: 24, length: 1) == 1 // 1 = South
            let nsVelocity = Int(bitValue(bits, offset: 25, length: 10)) - 1
            guard ewVelocity >= 0, nsVelocity >= 0 else { return false }

            let east = Double(ewDirection ? -ewVelocity : ewVelocity)
            let north = Double(nsDirection ? -nsVelocity : nsVelocity)
            aircraft.speed = Int(hypot(east, north).rounded())
            aircraft.track = fmod(atan2(east, north) * 180 / .pi + 360, 360)

        case 3, 4:
            // Airspeed + magnetic/true heading (used when GNSS unavailable)
            let headingAvailable = bitValue(bits, offset: 13, length: 1) != 0
            if headingAvailable {
                let headingRaw = Int(bitValue(bits, offset: 14, length: 10))
                aircraft.track = Double(headingRaw) * (360.0 / 1024.0)
            }
            let airspeed = Int(bitValue(bits, offset: 25, length: 10)) - 1
            if airspeed >= 0 {
                // Subtype 4 = supersonic: value is in 4-kt increments
                aircraft.speed = subtype == 4 ? airspeed * 4 : airspeed
            }

        default:
            return false
        }

        let verticalRateSign = bitValue(bits, offset: 36, length: 1) == 1
        let verticalRateValue = Int(bitValue(bits, offset: 37, length: 9)) - 1
        if verticalRateValue >= 0 {
            aircraft.verticalRate = (verticalRateSign ? -1 : 1) * verticalRateValue * 64
        }
        return true
    }

    // MARK: - CPR position resolution

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
            (Double(even.longitude) * Double(cprNL(latitude) - 1) - Double(odd.longitude) * Double(cprNL(latitude))) / 131072.0 + 0.5
        )
        let longitude = 360.0 / longitudeZone * (mod(m, longitudeZone) + Double(useEven ? even.longitude : odd.longitude) / 131072.0)
        let normalizedLongitude = longitude > 180 ? longitude - 360 : longitude
        return CLLocationCoordinate2D(latitude: latitude, longitude: normalizedLongitude)
    }

    // Surface CPR uses 1/4 the zone sizes of airborne CPR (dlat = 1.5° even, 90/59° odd)
    private func resolveGlobalSurfaceCPR(even: CPRFrame?, odd: CPRFrame?) -> CLLocationCoordinate2D? {
        guard let even, let odd else { return nil }
        guard abs(even.timestamp.timeIntervalSince(odd.timestamp)) <= 10 else { return nil }

        let evenLat = Double(even.latitude) / 131072.0
        let oddLat = Double(odd.latitude) / 131072.0
        let j = floor(59.0 * evenLat - 60.0 * oddLat + 0.5)
        var latitudeEven = 1.5 * (mod(j, 60.0) + evenLat)
        var latitudeOdd = (90.0 / 59.0) * (mod(j, 59.0) + oddLat)

        if latitudeEven >= 270 { latitudeEven -= 360 }
        if latitudeOdd >= 270 { latitudeOdd -= 360 }
        guard cprNL(latitudeEven) == cprNL(latitudeOdd) else { return nil }

        let useEven = even.timestamp > odd.timestamp
        let latitude = useEven ? latitudeEven : latitudeOdd
        let ni = max(useEven ? cprNL(latitude) : cprNL(latitude) - 1, 1)
        let longitudeZone = Double(ni)
        let m = floor(
            (Double(even.longitude) * Double(cprNL(latitude) - 1) - Double(odd.longitude) * Double(cprNL(latitude))) / 131072.0 + 0.5
        )
        let longitude = (90.0 / longitudeZone) * (mod(m, longitudeZone) + Double(useEven ? even.longitude : odd.longitude) / 131072.0)
        let normalizedLongitude = longitude > 180 ? longitude - 360 : longitude
        return CLLocationCoordinate2D(latitude: latitude, longitude: normalizedLongitude)
    }

    // MARK: - CPR NL lookup table

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

    // MARK: - Bit helpers

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
