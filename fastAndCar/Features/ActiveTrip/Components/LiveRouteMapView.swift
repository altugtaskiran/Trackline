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
    /// Locked (`[]`) while actively recording — the whole point is a
    /// steady chase-cam, not something to pan away from mid-drive. The
    /// idle/browsing state (DashboardView, not recording) passes
    /// `[.pan, .zoom]` so route discovery can work like a normal map.
    var interactionModes: MapInteractionModes = []
    /// Nearby popular routes to draw as tappable colored lines — only
    /// populated while idle (see DashboardView's route-discovery layer).
    var discoverySegments: [Segment] = []
    var selectedSegmentId: String?
    var onSelectSegment: ((String?) -> Void)?
    /// Forwards the map's own settled viewport after a pan/zoom gesture
    /// ends — DashboardView uses this to refetch nearby routes for the
    /// newly visible area. `.onEnd` already only fires once per gesture,
    /// so no extra debouncing is needed on top of it.
    var onRegionChange: ((MKCoordinateRegion) -> Void)?

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
                Map(position: $cameraPosition, interactionModes: interactionModes) { }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                    .environment(\.colorScheme, .light)
                    .opacity(0.22)
                    .onMapCameraChange(frequency: .onEnd) { context in
                        onRegionChange?(context.region)
                    }

                RouteOverlayCanvas(
                    samples: samples,
                    ghostRouteCoordinates: ghostRouteCoordinates,
                    crewMarkers: crewMarkers,
                    discoverySegments: discoverySegments,
                    selectedSegmentId: selectedSegmentId,
                    proxy: proxy
                )
                    .allowsHitTesting(!discoverySegments.isEmpty)
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                onSelectSegment?(nearestDiscoverySegment(to: value.location, proxy: proxy))
                            }
                    )
            }
        }
    }

    /// Nearest-point-on-polyline hit test in screen space — SwiftUI's `Map`
    /// gives no tap callback for `MapPolyline` content, so route selection
    /// has to be done by hand the same way the route/crew dots above are
    /// drawn by hand (MapReader's `proxy.convert`, not native map content).
    private func nearestDiscoverySegment(to point: CGPoint, proxy: MapProxy) -> String? {
        let tapRadius: CGFloat = 22
        var bestId: String?
        var bestDistance = tapRadius
        for segment in discoverySegments {
            let points = segment.polyline.compactMap { proxy.convert(CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon), to: .local) }
            guard points.count > 1 else { continue }
            for index in 1..<points.count {
                let distance = point.distanceToSegment(from: points[index - 1], to: points[index])
                if distance < bestDistance {
                    bestDistance = distance
                    bestId = segment.id
                }
            }
        }
        return bestId
    }
}

private extension CGPoint {
    /// Shortest distance from this point to the line segment a—b.
    func distanceToSegment(from a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(x - a.x, y - a.y) }
        let t = max(0, min(1, ((x - a.x) * dx + (y - a.y) * dy) / lengthSquared))
        let projectedX = a.x + t * dx
        let projectedY = a.y + t * dy
        return hypot(x - projectedX, y - projectedY)
    }
}

/// Deterministic per-route color — the same segment always renders the same
/// hue across launches/sessions, and different routes visibly differ.
func routeDiscoveryColor(for segmentId: String) -> Color {
    let hue = Double(abs(segmentId.hashValue) % 360) / 360.0
    return Color(hue: hue, saturation: 0.75, brightness: 0.95)
}

/// Draws the heatmap-colored route in screen space using MapReader's live
/// coordinate conversion, so it tracks the map's camera exactly without
/// being part of the (deliberately faded) Map content itself.
private struct RouteOverlayCanvas: View {
    let samples: [LocationSample]
    var ghostRouteCoordinates: [CLLocationCoordinate2D] = []
    var crewMarkers: [CrewMapMarker] = []
    var discoverySegments: [Segment] = []
    var selectedSegmentId: String?
    let proxy: MapProxy

    var body: some View {
        TimelineView(.animation(paused: samples.count < 2 && ghostRouteCoordinates.isEmpty && crewMarkers.isEmpty && discoverySegments.isEmpty)) { _ in
            Canvas { context, _ in
                // Unselected routes drawn first (dimmer, thinner) so the
                // selected one — drawn last, below — always sits on top.
                for segment in discoverySegments where segment.id != selectedSegmentId {
                    drawDiscoverySegment(segment, isSelected: false, context: context)
                }
                if let selectedSegmentId, let selected = discoverySegments.first(where: { $0.id == selectedSegmentId }) {
                    drawDiscoverySegment(selected, isSelected: true, context: context)
                }

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

    private func drawDiscoverySegment(_ segment: Segment, isSelected: Bool, context: GraphicsContext) {
        let points = segment.polyline.compactMap { proxy.convert(CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon), to: .local) }
        guard points.count > 1 else { return }
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        let color = routeDiscoveryColor(for: segment.id)
        context.stroke(
            path,
            with: .color(isSelected ? color : color.opacity(0.45)),
            style: StrokeStyle(lineWidth: isSelected ? 7 : 4, lineCap: .round, lineJoin: .round)
        )
    }
}
