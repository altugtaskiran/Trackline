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
    /// Recording's faint 0.22 backdrop is deliberate (a HUD, not something
    /// to actually read street names on) — but discovery routes are now
    /// native Map content (see body's comment), so that same opacity would
    /// wash *them* out too. Idle/browsing mode wants a genuinely legible
    /// map anyway (it's a real navigable surface now), so it passes 1.0.
    var mapOpacity: Double = 0.22
    /// The idle "you are here" marker's coordinate — from our own
    /// LocationManager (kept warm by DashboardView's startIdleMapTracking),
    /// never MapKit's own UserAnnotation. Two reasons: (1) UserAnnotation
    /// runs a second, independent CLLocationManager alongside ours, and the
    /// two concurrent location clients measurably slowed down our own
    /// manager's fix right when a drive started (confirmed live); (2) it's
    /// native Annotation content, not the screen-space Canvas below — a
    /// single point drawn in that Canvas visibly lagged/slid during an
    /// interactive drag (confirmed live: the reprojection there is driven
    /// by a TimelineView tick, not the drag gesture itself), while native
    /// content repositions immediately, every frame, for free.
    var idlePositionCoordinate: CLLocationCoordinate2D?

    var body: some View {
        MapReader { proxy in
            ZStack {
                // Discovery routes are native MapPolyline/Annotation content
                // here (not the screen-space Canvas below) on purpose: an
                // earlier attempt drew them in the Canvas and used a SwiftUI
                // tap gesture on an overlay to select them — even
                // .simultaneousGesture fought with the Map's own native
                // pinch/pan recognizers and broke free pan/zoom entirely
                // (confirmed live). Native Map content has no such conflict;
                // annotations are designed to coexist with map gestures.
                Map(position: $cameraPosition, interactionModes: interactionModes) {
                    if let idlePositionCoordinate {
                        // A plain String literal here resolves to
                        // Annotation's non-localizing StringProtocol
                        // overload, not the LocalizedStringKey one Text
                        // uses — it never picked up the app's language
                        // override or the system language at all
                        // (confirmed live: stayed Turkish even with the
                        // device set to English). Forcing LocalizedStringKey
                        // routes it through the same lookup Text(_:) uses.
                        Annotation(LocalizedStringKey("Konum"), coordinate: idlePositionCoordinate) {
                            Circle()
                                .fill(AppColor.accent)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                        }
                    }
                    ForEach(discoverySegments) { segment in
                        discoveryMapContent(for: segment)
                    }
                }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                    .environment(\.colorScheme, .light)
                    .opacity(mapOpacity)
                    .onMapCameraChange(frequency: .onEnd) { context in
                        onRegionChange?(context.region)
                    }

                RouteOverlayCanvas(samples: samples, ghostRouteCoordinates: ghostRouteCoordinates, crewMarkers: crewMarkers, proxy: proxy)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Discovery routes only ever draw a start-point pin while idle — the
    /// full colored line only appears for whichever one is currently
    /// selected. Two problems this solves at once (see LiveRouteMapView's
    /// header comment for the earlier gesture-conflict history this
    /// builds on): routes sharing the same road used to draw overlapping
    /// lines all the time (pure visual noise, nothing to tap), and a long
    /// route's one tappable point (used to be its geometric midpoint)
    /// could be far from wherever the user was actually looking, so a
    /// near-miss tap became a map pan that could drop the route out of
    /// the viewport entirely. Starting the pin at the route's actual
    /// start coordinate is also just more honest — that's where a drive
    /// following it would begin.
    @MapContentBuilder
    private func discoveryMapContent(for segment: Segment) -> some MapContent {
        let color = routeDiscoveryColor(for: segment.id)
        let isSelected = segment.id == selectedSegmentId

        if isSelected {
            MapPolyline(coordinates: segment.polyline.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        }

        if let start = segment.startCoordinate {
            Annotation(segment.name, coordinate: start) {
                DiscoveryRouteTapTarget(color: color, size: 22) {
                    onSelectSegment?(isSelected ? nil : segment.id)
                }
            }
        }
    }
}

/// The tappable dot marking a discovery route's start point — a plain
/// SwiftUI View (not an inline closure) so the enclosing MapContentBuilder
/// expression stays small enough for the compiler to type-check quickly.
private struct DiscoveryRouteTapTarget: View {
    let color: Color
    var size: CGFloat = 22
    var onTap: () -> Void

    var body: some View {
        ZStack {
            // A near-miss tap used to fall through to the Map's own pan
            // gesture instead of hitting this dot — a 44pt hit area
            // (Apple's own minimum tap-target guideline) around the same
            // visible dot fixes that without changing how it looks.
            Color.clear.frame(width: 44, height: 44)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        }
        .contentShape(Circle())
        .onTapGesture(perform: onTap)
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

                // Only draw the separate "start" dot once there's an actual
                // route (2+ points) — with just the single idle position
                // point, this would otherwise draw right on top of the
                // current-position dot below.
                if points.count > 1, let startPoint = points.first ?? nil {
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
