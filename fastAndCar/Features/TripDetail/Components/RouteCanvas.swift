//
//  RouteCanvas.swift
//  fastAndCar
//
//  The core "F1 track map" renderer: a pure line, no basemap, colored by
//  speed. Reused at every size — tiny Home row thumbnails, the Trip Detail
//  hero, and the Share Card. Canvas draws directly (no per-segment views),
//  so it stays smooth even for long routes.
//
//  `progress` (0...1) lets the same renderer draw a live-growing line during
//  Active Trip and Playback without any extra code path.
//

import SwiftUI

struct RouteCanvas: View {
    let samples: [LocationSample]
    var lineWidth: CGFloat = 3
    var showsEndpoints: Bool = true
    var padding: CGFloat = 16
    var progress: Double?
    /// Overridable so Trip Detail can swap in a projection registered to the
    /// real map underneath (see GeoMapProjector) instead of this default,
    /// which fits the route to its own view bounds with no map involved.
    var projector: ([LocationSample], CGRect, CGFloat) -> [CGPoint] = RouteProjector.project

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let points = projector(samples, rect, padding)
            guard points.count > 1 else { return }

            let visibleCount: Int
            if let progress {
                visibleCount = max(2, min(points.count, Int((Double(points.count) * progress).rounded(.up))))
            } else {
                visibleCount = points.count
            }

            for index in 1..<visibleCount {
                var segment = Path()
                segment.move(to: points[index - 1])
                segment.addLine(to: points[index])
                let color = AppColor.heatmapColor(forSpeedKph: samples[index].speedKph)
                context.stroke(
                    segment,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
            }

            guard showsEndpoints else { return }

            let dotRadius = max(lineWidth * 1.4, 4)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: AppColor.routeStart, radius: dotRadius * 1.3))
                layer.fill(Path(ellipseIn: dotRect(center: points[0], radius: dotRadius)), with: .color(AppColor.routeStart))
            }

            let endPoint = points[visibleCount - 1]
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: AppColor.routeEnd, radius: dotRadius * 1.3))
                layer.fill(Path(ellipseIn: dotRect(center: endPoint, radius: dotRadius)), with: .color(AppColor.routeEnd))
            }
        }
    }

    private func dotRect(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
