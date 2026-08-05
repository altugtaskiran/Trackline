//
//  GeoMapProjector.swift
//  fastAndCar
//
//  Projects a coordinate into a rect using the exact same linear mapping a
//  SwiftUI Map renders its `region` with (an equirectangular approximation —
//  indistinguishable from true Mercator over a route-sized span of a few
//  kilometers). Pairs with FittedRegion so a route line computed from this
//  always lands exactly on the real map underneath, whatever region that map
//  was given.
//

import CoreGraphics
import CoreLocation
import MapKit

enum GeoMapProjector {
    static func project(coordinate: CLLocationCoordinate2D, region: MKCoordinateRegion, into rect: CGRect) -> CGPoint {
        let lonSpan = region.span.longitudeDelta
        let latSpan = region.span.latitudeDelta
        guard lonSpan > 0, latSpan > 0 else { return CGPoint(x: rect.midX, y: rect.midY) }

        let minLon = region.center.longitude - lonSpan / 2
        let maxLat = region.center.latitude + latSpan / 2

        let x = rect.minX + CGFloat((coordinate.longitude - minLon) / lonSpan) * rect.width
        let y = rect.minY + CGFloat((maxLat - coordinate.latitude) / latSpan) * rect.height
        return CGPoint(x: x, y: y)
    }

    /// Matches `RouteProjector.project`'s (samples, rect, padding) -> [CGPoint]
    /// shape so it can be dropped into RouteCanvas / RouteInspectorOverlay /
    /// RouteEndpointLabels as a direct substitute for the default fit-to-own-
    /// rect projector. `padding` is unused — FittedRegion already bakes its
    /// margin into the region itself.
    static func projector(region: MKCoordinateRegion) -> ([LocationSample], CGRect, CGFloat) -> [CGPoint] {
        { samples, rect, _ in samples.map { project(coordinate: $0.coordinate, region: region, into: rect) } }
    }
}
