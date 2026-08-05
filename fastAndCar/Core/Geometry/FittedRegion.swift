//
//  FittedRegion.swift
//  fastAndCar
//
//  Computes a MKCoordinateRegion covering a route's samples, pre-adjusted to
//  a target pixel aspect ratio. Handing a Map a region that doesn't match its
//  view's aspect ratio makes MapKit silently pad one axis to fill the frame —
//  and anything projected independently (RouteProjector's own fit-to-rect,
//  for instance) has no way to know how much padding MapKit chose, so a route
//  line drawn from that separate projection drifts off the real streets
//  underneath. Fitting the aspect ratio ourselves up front removes that
//  unknown: MapKit renders the region as given, with nothing left to guess.
//

import CoreLocation
import Foundation
import MapKit

enum FittedRegion {
    static func fitting(samples: [LocationSample], aspectRatio: Double, paddingFraction: Double = 0.3) -> MKCoordinateRegion {
        guard let first = samples.first, aspectRatio.isFinite, aspectRatio > 0 else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }

        let latitudes = samples.map(\.latitude)
        let longitudes = samples.map(\.longitude)
        let minLat = latitudes.min() ?? first.latitude
        let maxLat = latitudes.max() ?? first.latitude
        let minLon = longitudes.min() ?? first.longitude
        let maxLon = longitudes.max() ?? first.longitude
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)

        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = 111_320.0 * cos(center.latitude * .pi / 180)

        let minSpanMeters = 200.0 // stationary or near-stationary trips still get a sensible zoom level
        var latSpanMeters = max((maxLat - minLat) * metersPerDegreeLatitude, minSpanMeters)
        var lonSpanMeters = max((maxLon - minLon) * metersPerDegreeLongitude, minSpanMeters)

        latSpanMeters *= 1 + paddingFraction * 2
        lonSpanMeters *= 1 + paddingFraction * 2

        // Grow (never shrink) whichever axis is under the target aspect, so
        // every sample stays inside the region while the region's own shape
        // ends up exactly matching the view it'll be rendered into.
        let currentAspect = lonSpanMeters / latSpanMeters
        if currentAspect < aspectRatio {
            lonSpanMeters = latSpanMeters * aspectRatio
        } else {
            latSpanMeters = lonSpanMeters / aspectRatio
        }

        let span = MKCoordinateSpan(
            latitudeDelta: latSpanMeters / metersPerDegreeLatitude,
            longitudeDelta: lonSpanMeters / metersPerDegreeLongitude
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
