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
    /// mode. Static once armed, so native MapPolyline content is fine for
    /// it (no smoothing needed) even though the live trail below isn't.
    var ghostRouteCoordinates: [CLLocationCoordinate2D] = []

    @State private var cameraPosition: MapCameraPosition

    // Same real-GPS-interval-based smoothing as the 2D map's
    // RouteOverlayCanvas (LiveRouteMapView.swift) — raw samples land
    // roughly once a second regardless of speed, and drawing straight at
    // samples.last made the position dot visibly jump/pause-then-jump at
    // high speed. Easing over the real gap between each sample's own
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
        MapReader { proxy in
            ZStack {
                TimelineView(.animation(paused: samples.count < 2)) { timeline in
                    mapContent(at: timeline.date, proxy: proxy)
                }
            }
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
    private func routeContent() -> some MapContent {
        if ghostRouteCoordinates.count > 1 {
            MapPolyline(coordinates: ghostRouteCoordinates)
                .stroke(Color(hex: 0xBF5AF2).opacity(0.7), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [2, 10]))
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

    private func mapContent(at date: Date, proxy: MapProxy) -> some View {
        let smoothedCurrent = displayCoordinate(at: date)
        return ZStack {
            Map(position: $cameraPosition, interactionModes: []) {
                routeContent()
            }
            .mapStyle(.hybrid(elevation: .realistic))

            // The trailing route line AND the car icon are both drawn
            // here, in this one Canvas, line first then car on top — same
            // order 2D's RouteOverlayCanvas already used successfully.
            // They used to be split (line in a separate Canvas layer, car
            // as native Annotation content inside the Map) — a later
            // ZStack layer always paints over an earlier one regardless
            // of any real 3D depth relationship, so the line (added after
            // the Map) was drawing on top of the car every time,
            // sometimes in front of it (confirmed live — a real bug, not
            // a simulator artifact). Drawing both in one Canvas, car
            // last, fixes the ordering for good.
            TrailAndCarOverlayCanvas(samples: samples, dotCoordinate: smoothedCurrent, proxy: proxy)
                .allowsHitTesting(false)
        }
    }

    private func updateCamera() {
        guard let last else { return }
        let camera = MapCamera(centerCoordinate: last.coordinate, distance: 350, heading: last.heading ?? 0, pitch: 60)
        withAnimation(.linear(duration: 0.9)) {
            cameraPosition = .camera(camera)
        }
    }
}

/// Draws just the growing driven-route trail in screen space, same
/// technique as LiveRouteMapView's RouteOverlayCanvas — a live redraw
/// tracks the map's current camera exactly on every frame, which a native
/// MapPolyline replaced every frame cannot do smoothly.
private struct TrailAndCarOverlayCanvas: View {
    let samples: [LocationSample]
    let dotCoordinate: CLLocationCoordinate2D?
    let proxy: MapProxy

    var body: some View {
        // No TimelineView of its own — the parent (mapContent(at:proxy:))
        // already rebuilds this fresh every frame from the outer
        // TimelineView in body, so samples/dotCoordinate here are already
        // current for this tick.
        Canvas { context, _ in
            let points = samples.map { proxy.convert($0.coordinate, to: .local) }
            if points.count > 1 {
                for index in 1..<points.count {
                    guard let previous = points[index - 1], let current = points[index] else { continue }
                    var segment = Path()
                    segment.move(to: previous)
                    segment.addLine(to: current)
                    context.stroke(
                        segment,
                        with: .color(AppColor.heatmapColor(forSpeedKph: samples[index].speedKph)),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                    )
                }
            }

            // Car drawn last — on top of the line, matching 2D's own
            // RouteOverlayCanvas draw order.
            guard let dotCoordinate, let dotPoint = proxy.convert(dotCoordinate, to: .local) else { return }
            context.drawLayer { layer in
                layer.translateBy(x: dotPoint.x, y: dotPoint.y)
                layer.addFilter(.shadow(color: .black.opacity(0.35), radius: 4))
                switch LocationMarkerStyle.current {
                case .dot:
                    let radius: CGFloat = 8
                    let rect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
                    layer.fill(Path(ellipseIn: rect), with: .color(AppColor.accent))
                    layer.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2)
                case .carTest:
                    let carSize: CGFloat = 38
                    layer.draw(Image("LocationCar"), in: CGRect(x: -carSize / 2, y: -carSize / 2, width: carSize, height: carSize))
                }
            }
        }
    }
}
