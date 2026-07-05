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

private struct MyLocationButton: View {
    let hasLocation: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: hasLocation ? "location.fill" : "location")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hasLocation ? Color(red: 0.545, green: 0.361, blue: 0.965) : .secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 34, height: 34)
        .background(.ultraThinMaterial, in: Circle())
        .overlay { Circle().stroke(.white.opacity(0.18), lineWidth: 1) }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .help(hasLocation ? "Center on my location" : "Location not available")
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

    // Stored in @State so MapKit's content builder sees a concrete value change.
    @State private var radarRadius: CLLocationDistance = 100_000

    private var ringCenter: CLLocationCoordinate2D {
        viewModel.userLocation ?? CLLocationCoordinate2D(
            latitude: viewModel.config.mapCenterLat,
            longitude: viewModel.config.mapCenterLon
        )
    }

    private let ringColor = Color(red: 0.545, green: 0.361, blue: 0.965)

    private func updatedRadarRadius() -> CLLocationDistance {
        let fallback: CLLocationDistance = 100_000
        guard !viewModel.aircraft.isEmpty else { return fallback }
        let center = CLLocation(latitude: ringCenter.latitude, longitude: ringCenter.longitude)
        let maxDist = viewModel.aircraft.map { ac in
            CLLocation(latitude: ac.position.latitude, longitude: ac.position.longitude)
                .distance(from: center)
        }.max() ?? fallback
        return Swift.max(maxDist * 1.15, fallback)
    }

    var body: some View {
        Map(position: $cameraPosition) {
            MapCircle(center: ringCenter, radius: radarRadius)
                .foregroundStyle(ringColor.opacity(0.10))
                .stroke(ringColor.opacity(0.55), lineWidth: 2)

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
        .overlay(alignment: .bottomTrailing) {
            MyLocationButton(hasLocation: viewModel.userLocation != nil) {
                let center = viewModel.userLocation ?? CLLocationCoordinate2D(
                    latitude: viewModel.config.mapCenterLat,
                    longitude: viewModel.config.mapCenterLon
                )
                withAnimation(.easeInOut(duration: 0.4)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: center,
                        span: MKCoordinateSpan(latitudeDelta: 2.5, longitudeDelta: 2.5)
                    ))
                }
            }
            .padding(14)
        }
        .task {
            viewModel.startLocationUpdates()
            radarRadius = updatedRadarRadius()
        }
        .onChange(of: viewModel.aircraft.count) { _, _ in
            radarRadius = updatedRadarRadius()
        }
        .onChange(of: viewModel.userLocation != nil) { _, _ in
            radarRadius = updatedRadarRadius()
        }
    }
}
