import SwiftUI

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .font(.caption)
    }
}

struct TelemetryCell: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }
}

struct InspectorView: View {
    let aircraft: Aircraft
    let onClose: () -> Void

    private var altitudeColor: Color {
        switch aircraft.altitude {
        case ..<5000: return .green
        case 5000..<15000: return .blue
        case 15000..<30000: return Color(red: 0.545, green: 0.361, blue: 0.965)
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(altitudeColor)
                            .frame(width: 8, height: 8)
                        Text(aircraft.callsign ?? aircraft.id.uppercased())
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    if let reg = aircraft.registration {
                        Text(reg)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if aircraft.aircraftType != nil || aircraft.airline != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            if let type = aircraft.aircraftType {
                                InfoRow(icon: "airplane", label: "Type", value: type)
                            }
                            if let airline = aircraft.airline {
                                InfoRow(icon: "building.2", label: "Operator", value: airline)
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(8)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("TELEMETRY")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .tracking(1)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            TelemetryCell(
                                label: "Altitude",
                                value: aircraft.altitude == 0 ? "GND" : aircraft.altitude.formatted(),
                                unit: aircraft.altitude == 0 ? "" : "ft"
                            )
                            TelemetryCell(label: "Speed", value: "\(aircraft.speed)", unit: "kts")
                            TelemetryCell(
                                label: "Track",
                                value: String(format: "%.0f°", aircraft.track),
                                unit: ""
                            )
                            TelemetryCell(
                                label: "V/S",
                                value: aircraft.verticalRate > 0
                                    ? "+\(aircraft.verticalRate)"
                                    : "\(aircraft.verticalRate)",
                                unit: "fpm"
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if let squawk = aircraft.squawk {
                            InfoRow(icon: "antenna.radiowaves.left.and.right", label: "Squawk", value: squawk)
                        }
                        if let cat = aircraft.category {
                            InfoRow(icon: "tag", label: "Category", value: cat)
                        }
                        InfoRow(icon: "doc.text", label: "ICAO24", value: aircraft.id.uppercased())
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(8)
                }
                .padding()
            }
        }
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 4)
    }
}
