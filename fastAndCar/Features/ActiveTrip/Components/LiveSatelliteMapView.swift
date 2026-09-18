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

    @State private var cameraPosition: MapCameraPosition

    private var last: LocationSample? { samples.last }

    init(samples: [LocationSample]) {
        self.samples = samples
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
