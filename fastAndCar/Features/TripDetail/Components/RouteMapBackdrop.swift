//
//  RouteMapBackdrop.swift
//  fastAndCar
//
//  Muted map framed to the whole trip, sitting behind RouteCanvas's crisp
//  route line on the review screen. `region` is computed once by the caller
//  (FittedRegion, aspect-matched to the card) and shared with RouteCanvas via
//  GeoMapProjector, so the line stays pixel-registered to the real streets
//  underneath rather than drifting off them. Rendered as its own layer (not
//  inside a Map with the route drawn on it), so its opacity can sit fairly
//  high without ever softening the route line on top. Static (no
//  interaction) — this card sits inside Trip Detail's outer ScrollView and
//  shares space with RouteInspectorOverlay's tap-to-inspect gesture, so it's
//  a fixed backdrop rather than an independently zoomable map.
//

import MapKit
import SwiftUI

struct RouteMapBackdrop: View {
    let region: MKCoordinateRegion

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: []) {}
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .environment(\.colorScheme, .light)
            .opacity(0.6)
    }
}
