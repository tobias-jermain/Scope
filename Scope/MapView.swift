import SwiftUI
import MapKit

struct AircraftAnnotationView: View {
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

    private var iconSize: CGFloat {
        if isSelected { return 18 }
        if aircraft.altitude < 5000 { return 10 }
        if aircraft.altitude < 15000 { return 12 }
        return 14
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.yellow.opacity(0.25) : Color.black.opacity(0.35))
                    .frame(width: iconSize + 8, height: iconSize + 8)

                Image(systemName: "airplane")
                    .font(.system(size: iconSize))
                    .foregroundStyle(isSelected ? .yellow : altitudeColor)
                    .rotationEffect(.degrees(aircraft.track - 45))
            }

            if isSelected, let cs = aircraft.callsign {
                Text(cs)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.65))
                    .cornerRadius(3)
            }
        }
    }
}

struct MapView: View {
    @ObservedObject var viewModel: AircraftViewModel
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.022, longitude: 0.330),
            span: MKCoordinateSpan(latitudeDelta: 2.5, longitudeDelta: 2.5)
        )
    )

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(viewModel.aircraft) { aircraft in
                Annotation("", coordinate: aircraft.position, anchor: .center) {
                    AircraftAnnotationView(
                        aircraft: aircraft,
                        isSelected: viewModel.selectedAircraft?.id == aircraft.id
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedAircraft = aircraft
                        }
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
    }
}
