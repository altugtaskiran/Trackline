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

    // Same real-GPS-interval-based smoothing as the 2D map's
    // RouteOverlayCanvas (LiveRouteMapView.swift) — raw samples land
    // roughly once a second regardless of speed, and drawing straight at
    // samples.last made both the position dot and the trailing polyline
    // visibly jump/pause-then-jump at high speed (confirmed live, and
    // reported as still happening here in 3D after the 2D map was already
    // fixed). Easing over the real gap between each sample's own
    // timestamp keeps motion continuous at any speed, with no pause.
    @State private var transitionStartCoordinate: CLLocationCoordinate2D?
    @State private var transitionStartTime: Date = .now
    @State private var transitionDuration: TimeInterval = 1.0

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

    private func displayCoordinate(at date: Date) -> CLLocationCoordinate2D? {
        guard let target = last?.coordinate else { return nil }
        guard let start = transitionStartCoordinate else { return target }
        let t = min(1, max(0, date.timeIntervalSince(transitionStartTime) / transitionDuration))
        return CLLocationCoordinate2D(
            latitude: start.latitude + (target.latitude - start.latitude) * t,
            longitude: start.longitude + (target.longitude - start.longitude) * t
        )
    }

    var body: some View {
        TimelineView(.animation(paused: samples.count < 2)) { timeline in
            mapContent(at: timeline.date)
        }
        .onChange(of: last?.id) { _, _ in
            updateCamera()

            guard let newSample = samples.last, let previousSample = samples.dropLast().last else {
                transitionStartCoordinate = nil
                transitionStartTime = .now
                return
            }
            let interval = newSample.timestamp.timeIntervalSince(previousSample.timestamp)
            if interval > 0.3 && interval <= 3.0 {
                transitionStartCoordinate = previousSample.coordinate
                transitionDuration = interval
            } else {
                // No usable interval (first sample, out-of-order, or a
                // signal-loss-sized gap) — snap instead of slowly creeping
                // across what might be a huge real jump.
                transitionStartCoordinate = nil
            }
            transitionStartTime = .now
        }
    }

    @MapContentBuilder
    private func routeContent(polylineCoordinates: [CLLocationCoordinate2D], dotCoordinate: CLLocationCoordinate2D?) -> some MapContent {
        if ghostRouteCoordinates.count > 1 {
            MapPolyline(coordinates: ghostRouteCoordinates)
                .stroke(Color(hex: 0xBF5AF2).opacity(0.7), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [2, 10]))
        }
        if polylineCoordinates.count > 1 {
            MapPolyline(coordinates: polylineCoordinates)
                .stroke(AppColor.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
        if let dotCoordinate {
            // Empty title — see LiveRouteMapView's idle position
            // annotation for why (unwanted permanent "Konum" label).
            Annotation("", coordinate: dotCoordinate) {
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

    private func mapContent(at date: Date) -> some View {
        let smoothedCurrent = displayCoordinate(at: date)
        var polylineCoordinates = samples.map(\.coordinate)
        if !polylineCoordinates.isEmpty, let smoothedCurrent {
            polylineCoordinates[polylineCoordinates.count - 1] = smoothedCurrent
        }
        return Map(position: $cameraPosition, interactionModes: []) {
            routeContent(polylineCoordinates: polylineCoordinates, dotCoordinate: smoothedCurrent)
        }
        .mapStyle(.hybrid(elevation: .realistic))
    }

    private func updateCamera() {
        guard let last else { return }
        let camera = MapCamera(centerCoordinate: last.coordinate, distance: 350, heading: last.heading ?? 0, pitch: 60)
        withAnimation(.linear(duration: 0.9)) {
            cameraPosition = .camera(camera)
        }
    }
}
