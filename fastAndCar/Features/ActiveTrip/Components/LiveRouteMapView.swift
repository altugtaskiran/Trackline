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

import MapKit
import SwiftUI

struct LiveRouteMapView: View {
    let samples: [LocationSample]
    @Binding var cameraPosition: MapCameraPosition

    var body: some View {
        MapReader { proxy in
            ZStack {
                Map(position: $cameraPosition, interactionModes: []) {}
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                    .environment(\.colorScheme, .light)
                    .opacity(0.22)

                RouteOverlayCanvas(samples: samples, proxy: proxy)
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
    let proxy: MapProxy

    var body: some View {
        Canvas { context, _ in
            let points = samples.map { proxy.convert($0.coordinate, to: .local) }
            guard points.count > 1 else { return }

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

            if let startPoint = points.first ?? nil {
                let radius: CGFloat = 7
                let rect = CGRect(x: startPoint.x - radius, y: startPoint.y - radius, width: radius * 2, height: radius * 2)
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: AppColor.routeStart, radius: 8))
                    layer.fill(Path(ellipseIn: rect), with: .color(AppColor.routeStart))
                }
            }
        }
    }
}
