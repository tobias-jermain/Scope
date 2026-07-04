import SwiftUI

enum SortOption: String, CaseIterable {
    case altitude = "Alt"
    case speed = "Speed"
    case callsign = "Call"
}

struct SidebarRow: View {
    let aircraft: Aircraft
    let isSelected: Bool

    private var altitudeColor: Color {
        switch aircraft.altitude {
        case ..<5000: return .green
        case 5000..<15000: return .blue
        case 15000..<30000: return Color(red: 0.545, green: 0.361, blue: 0.965)
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(altitudeColor)
                .frame(width: 3, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(aircraft.callsign ?? aircraft.id.uppercased())
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer()
                    Text(aircraft.altitude == 0 ? "GND" : "\(aircraft.altitude.formatted())ft")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack {
                    if let type = aircraft.aircraftType {
                        Text(type)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let reg = aircraft.registration {
                        Text(reg)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(aircraft.id.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    HStack(spacing: 2) {
                        if aircraft.verticalRate > 200 {
                            Image(systemName: "arrow.up")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        } else if aircraft.verticalRate < -200 {
                            Image(systemName: "arrow.down")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                        Text("\(aircraft.speed)kt")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(6)
    }
}

struct SidebarView: View {
    @ObservedObject var viewModel: AircraftViewModel
    @State private var filterText = ""
    @State private var sortOption = SortOption.altitude

    private var filtered: [Aircraft] {
        let base: [Aircraft]
        if filterText.isEmpty {
            base = viewModel.aircraft
        } else {
            let q = filterText.lowercased()
            base = viewModel.aircraft.filter {
                $0.callsign?.lowercased().contains(q) == true ||
                $0.registration?.lowercased().contains(q) == true ||
                $0.aircraftType?.lowercased().contains(q) == true ||
                $0.id.contains(q)
            }
        }
        switch sortOption {
        case .altitude: return base.sorted { $0.altitude > $1.altitude }
        case .speed: return base.sorted { $0.speed > $1.speed }
        case .callsign: return base.sorted { ($0.callsign ?? $0.id) < ($1.callsign ?? $1.id) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                TextField("Search...", text: $filterText)
                    .textFieldStyle(.roundedBorder)

                Picker("Sort", selection: $sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(10)

            Divider()

            if viewModel.aircraft.isEmpty && viewModel.connectionState == .connected {
                VStack {
                    Spacer()
                    Image(systemName: "airplane.departure")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No aircraft in range")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    Spacer()
                }
            } else {
                List {
                    ForEach(filtered) { ac in
                        SidebarRow(aircraft: ac, isSelected: viewModel.selectedAircraft?.id == ac.id)
                            .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                            .listRowSeparator(.hidden)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.selectedAircraft = ac
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}
