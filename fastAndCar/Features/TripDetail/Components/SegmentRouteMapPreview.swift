//
//  SegmentRouteMapPreview.swift
//  fastAndCar
//
//  Static route preview for a Segment — SegmentDetailView, CrewSegmentDetailView
//  and CreateSegmentFlowView all used to draw this with RouteMapBackdrop +
//  RouteCanvas + GeoMapProjector (a hand-rolled equirectangular approximation
//  registered to a real Map's region). That approximation is "indistinguishable
//  from true Mercator over a route-sized span of a few kilometers" per its own
//  header comment — true for a short segment, but visibly wrong for a longer
//  one: the wider the region has to zoom out, the more the two projections
//  diverge, and the hand-drawn line drifts off the real streets underneath
//  (confirmed live). Native `MapPolyline`/`Annotation` content, rendered by
//  MapKit itself using its own real projection, can't drift from its own map
//  no matter how long the route is — same fix already applied to the Home
//  map's route-discovery layer (LiveRouteMapView).
//

import MapKit
import SwiftUI

struct SegmentRouteMapPreview: View {
    let coordinates: [CLLocationCoordinate2D]

    private var region: MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLat = latitudes.min() ?? first.latitude
        let maxLat = latitudes.max() ?? first.latitude
        let minLon = longitudes.min() ?? first.longitude
        let maxLon = longitudes.max() ?? first.longitude
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        // Generous padding — MapKit is free to fit this region however it
        // likes (unlike FittedRegion, nothing downstream needs to match its
        // choice pixel-for-pixel anymore), so there's no aspect-ratio math
        // to get right here, just enough margin that the line isn't flush
        // against the card's edges.
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.01)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: []) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(AppColor.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let start = coordinates.first {
                Annotation("Başlangıç", coordinate: start) {
                    Circle()
                        .fill(AppColor.routeStart)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.35), radius: 4)
                }
            }
            if let end = coordinates.last, coordinates.count > 1 {
                Annotation("Bitiş", coordinate: end) {
                    Circle()
                        .fill(AppColor.routeEnd)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.35), radius: 4)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .environment(\.colorScheme, .light)
    }
}
