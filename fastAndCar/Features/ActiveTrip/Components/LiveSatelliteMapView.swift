//
//  LiveSatelliteMapView.swift
//  fastAndCar
//
//  Faz 2, take two — a live "chase cam" for while you're actually driving,
//  not for reviewing a finished trip (that first attempt, pinned to a
//  playback scrubber over a Trip's already-recorded samples, tracked the
//  wrong point often enough to be unusable and was pulled). Here the camera
//  always follows the single most recent GPS fix, the same value
//  ActiveTripViewModel is already using for the live stat readouts — no
//  separate cursor/index to fall out of sync with the real position.
//

import CoreLocation
import MapKit
import SwiftUI

struct LiveSatelliteMapView: View {
    var samples: [LocationSample]
    var crewMarkers: [CrewMapMarker] = []
    /// The target Segment's own route, drawn as a fixed "ghost" reference
    /// line — same purple dashed styling as the 2D map's Route Following
    /// mode, just as native MapPolyline content instead of a Canvas overlay
    /// (this map has no MapReader/proxy layer to draw one in).
    var ghostRouteCoordinates: [CLLocationCoordinate2D] = []

    @State private var cameraPosition: MapCameraPosition

    private var last: LocationSample? { samples.last }

    init(samples: [LocationSample], crewMarkers: [CrewMapMarker] = [], ghostRouteCoordinates: [CLLocationCoordinate2D] = []) {
        self.samples = samples
        self.crewMarkers = crewMarkers
        self.ghostRouteCoordinates = ghostRouteCoordinates
        // Seeded from the real starting position (when one's already known)
        // instead of `.automatic` — `.automatic` briefly resolves to
        // MapKit's own default region before the first onChange can correct
        // it, which read as "shows a random place" the moment this mode
        // turned on.
        if let last = samples.last {
            _cameraPosition = State(initialValue: .camera(
                MapCamera(centerCoordinate: last.coordinate, distance: 350, heading: last.heading ?? 0, pitch: 60)
            ))
        } else {
            _cameraPosition = State(initialValue: .automatic)
        }
    }

    var body: some View {
        Map(position: $cameraPosition, interactionModes: []) {
            if ghostRouteCoordinates.count > 1 {
                MapPolyline(coordinates: ghostRouteCoordinates)
                    .stroke(Color(hex: 0xBF5AF2).opacity(0.7), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [2, 10]))
            }
            if samples.count > 1 {
                MapPolyline(coordinates: samples.map(\.coordinate))
                    .stroke(AppColor.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let last {
                Annotation("Konum", coordinate: last.coordinate) {
                    Circle()
                        .fill(AppColor.accent)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                }
            }
            ForEach(crewMarkers) { marker in
                Annotation(marker.nickname, coordinate: marker.coordinate) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: 0xBF5AF2))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                        Text(String(marker.nickname.prefix(1)).uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .onChange(of: last?.id) { _, _ in updateCamera() }
    }

    private func updateCamera() {
        guard let last else { return }
        let camera = MapCamera(centerCoordinate: last.coordinate, distance: 350, heading: last.heading ?? 0, pitch: 60)
        withAnimation(.linear(duration: 0.9)) {
            cameraPosition = .camera(camera)
        }
    }
}
