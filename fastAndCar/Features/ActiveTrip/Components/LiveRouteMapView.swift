//
//  LiveRouteMapView.swift
//  fastAndCar
//
//  Live-recording backdrop: a muted, pale-gray real street map (Apple's
//  built-in "muted" standard style, forced to light appearance) with the
//  growing route drawn on top, geographically accurate to the real streets
//  underneath. Non-interactive — this is a live display, not something to
//  pan/zoom away from mid-drive.
//
//  MapKit has no public toggle to hide street/area name labels. Applying low
//  opacity to the whole Map doesn't work either — dark label text blended
//  toward black over this app's black background stays dark, so it stays
//  legible even at low alpha; only the pale road fill actually fades. So the
//  route is drawn as a *separate* screen-space layer via MapReader instead
//  of as a MapPolyline inside the Map: the map itself can go very faint
//  (labels genuinely wash out) while the route stays fully opaque and crisp.
//
//  ActiveTripView animates `cameraPosition` (withAnimation) every time a new
//  sample lands, so the map camera is very often mid-transition. proxy.convert
//  only reflects the map's *current* on-screen geometry, so the overlay must
//  be redrawn every frame while that animation runs — otherwise the route
//  goes stale for up to 0.6s and visibly slides out of registration with the
//  streets underneath. TimelineView(.animation) forces that continuous
//  redraw instead of only redrawing when `samples` changes.
//

import MapKit
import SwiftUI

struct LiveRouteMapView: View {
    let samples: [LocationSample]
    @Binding var cameraPosition: MapCameraPosition
    /// The target Segment's own route, drawn as a fixed "ghost" reference
    /// line underneath the live-recorded route — Route Following mode's
    /// only UI besides the turn-hint banner, no MapKit routing involved.
    var ghostRouteCoordinates: [CLLocationCoordinate2D] = []
    /// Crewmates currently sharing their location, drawn as small purple
    /// dots on top of this same map — "is anyone I know nearby / headed
    /// the same way", without leaving the driving screen.
    var crewMarkers: [CrewMapMarker] = []

    var body: some View {
        MapReader { proxy in
            ZStack {
                // No UserAnnotation here on purpose: it tracks raw, unthrottled
                // CoreLocation updates, while the route below is drawn from
                // `samples` (throttled to ~1/sec + smoothed) — mixing the two
                // made the dot visibly run ahead of the line it was supposed to
                // sit on. The current-position dot is drawn in the same Canvas
                // below, from the same `samples` array, so it and the route
                // always agree exactly.
                Map(position: $cameraPosition, interactionModes: []) { }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                    .environment(\.colorScheme, .light)
                    .opacity(0.22)

                RouteOverlayCanvas(samples: samples, ghostRouteCoordinates: ghostRouteCoordinates, crewMarkers: crewMarkers, proxy: proxy)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Draws the heatmap-colored route in screen space using MapReader's live
/// coordinate conversion, so it tracks the map's camera exactly without
/// being part of the (deliberately faded) Map content itself.
private struct RouteOverlayCanvas: View {
    let samples: [LocationSample]
    var ghostRouteCoordinates: [CLLocationCoordinate2D] = []
    var crewMarkers: [CrewMapMarker] = []
    let proxy: MapProxy

    var body: some View {
        TimelineView(.animation(paused: samples.count < 2 && ghostRouteCoordinates.isEmpty && crewMarkers.isEmpty)) { _ in
            Canvas { context, _ in
                if ghostRouteCoordinates.count > 1 {
                    let ghostPoints = ghostRouteCoordinates.map { proxy.convert($0, to: .local) }
                    var ghostPath = Path()
                    var started = false
                    for point in ghostPoints {
                        guard let point else { continue }
                        if !started {
                            ghostPath.move(to: point)
                            started = true
                        } else {
                            ghostPath.addLine(to: point)
                        }
                    }
                    context.stroke(
                        ghostPath,
                        with: .color(Color(hex: 0xBF5AF2).opacity(0.7)),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [2, 10])
                    )
                }

                let points = samples.map { proxy.convert($0.coordinate, to: .local) }
                guard !points.isEmpty else { return }

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

                if let startPoint = points.first ?? nil {
                    let radius: CGFloat = 7
                    let rect = CGRect(x: startPoint.x - radius, y: startPoint.y - radius, width: radius * 2, height: radius * 2)
                    context.drawLayer { layer in
                        layer.addFilter(.shadow(color: AppColor.routeStart, radius: 8))
                        layer.fill(Path(ellipseIn: rect), with: .color(AppColor.routeStart))
                    }
                }

                // Current-position dot, drawn from the same `samples` the
                // route line above is drawn from (see body's comment) —
                // always exactly at the end of the line, never ahead of it.
                if let currentPoint = points.last ?? nil {
                    let radius: CGFloat = 8
                    let rect = CGRect(x: currentPoint.x - radius, y: currentPoint.y - radius, width: radius * 2, height: radius * 2)
                    context.drawLayer { layer in
                        layer.addFilter(.shadow(color: .black.opacity(0.35), radius: 4))
                        layer.fill(Path(ellipseIn: rect), with: .color(AppColor.accent))
                        layer.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2)
                    }
                }

                for marker in crewMarkers {
                    guard let point = proxy.convert(marker.coordinate, to: .local) else { continue }
                    let radius: CGFloat = 8
                    let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                    context.drawLayer { layer in
                        layer.addFilter(.shadow(color: .black.opacity(0.35), radius: 4))
                        layer.fill(Path(ellipseIn: rect), with: .color(Color(hex: 0xBF5AF2)))
                        layer.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2)
                    }
                    let label = Text(String(marker.nickname.prefix(1)).uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                    context.draw(label, at: point)
                }
            }
        }
    }
}
