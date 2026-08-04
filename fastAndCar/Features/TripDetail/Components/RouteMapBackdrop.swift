//
//  RouteMapBackdrop.swift
//  fastAndCar
//
//  Muted map framed to the whole trip, sitting behind RouteCanvas's crisp
//  abstract line on the review screen. The two aren't pixel-registered
//  (RouteCanvas fits the route to its own card shape rather than a true map
//  projection) — this is texture grounding the drive in its real streets.
//  Rendered as its own layer (not inside a Map with the route drawn on it),
//  so its opacity can sit fairly high without ever softening the route line
//  on top. Zoom/pan are enabled so the map can be explored; rotate/pitch
//  stay off to keep it predictable.
//

import MapKit
import SwiftUI

struct RouteMapBackdrop: View {
    let samples: [LocationSample]

    var body: some View {
        Map(initialPosition: .region(fittedRegion), interactionModes: [.zoom, .pan]) {}
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .environment(\.colorScheme, .light)
            .opacity(0.6)
    }

    private var fittedRegion: MKCoordinateRegion {
        guard let firstSample = samples.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }

        let latitudes = samples.map(\.latitude)
        let longitudes = samples.map(\.longitude)
        let minLat = latitudes.min() ?? firstSample.latitude
        let maxLat = latitudes.max() ?? firstSample.latitude
        let minLon = longitudes.min() ?? firstSample.longitude
        let maxLon = longitudes.max() ?? firstSample.longitude

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        // 1.6x the raw extent leaves roughly 30% padding on every side.
        let latDelta = max((maxLat - minLat) * 1.6, 0.004)
        let lonDelta = max((maxLon - minLon) * 1.6, 0.004)

        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }
}
