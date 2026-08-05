//
//  RouteProjector.swift
//  fastAndCar
//
//  Converts raw lat/lon samples into a local flat-earth projection, then fits
//  that shape into a target rect. This is what turns GPS coordinates into the
//  clean "F1 track map" line — no real map is ever involved.
//

import CoreGraphics
import Foundation

enum RouteProjector {
    /// Projects samples onto a local tangent plane (meters, x = east, y = north),
    /// then scales/centers the shape to fit `rect` with `padding` on every side,
    /// preserving aspect ratio. Returns one CGPoint per input sample, same order.
    nonisolated static func project(samples: [LocationSample], into rect: CGRect, padding: CGFloat = 24) -> [CGPoint] {
        guard let origin = samples.first, rect.width > 0, rect.height > 0 else { return [] }

        let meanLatitude = samples.reduce(0.0) { $0 + $1.latitude } / Double(samples.count)
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = 111_320.0 * cos(meanLatitude * .pi / 180)

        let flatPoints: [(x: Double, y: Double)] = samples.map { sample in
            let x = (sample.longitude - origin.longitude) * metersPerDegreeLongitude
            let y = (sample.latitude - origin.latitude) * metersPerDegreeLatitude
            return (x, y)
        }

        let xs = flatPoints.map(\.x)
        let ys = flatPoints.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return [] }

        let shapeWidth = maxX - minX
        let shapeHeight = maxY - minY
        let availableWidth = rect.width - padding * 2
        let availableHeight = rect.height - padding * 2

        let scaleX = shapeWidth > 0 ? Double(availableWidth) / shapeWidth : .infinity
        let scaleY = shapeHeight > 0 ? Double(availableHeight) / shapeHeight : .infinity
        var scale = min(scaleX, scaleY)
        // A stationary trip (or a straight N/S or E/W line) has zero width or
        // height; fall back to the other axis's scale, or 1 if both are zero.
        if !scale.isFinite {
            scale = [scaleX, scaleY].first(where: \.isFinite) ?? 1
        }

        let projectedWidth = CGFloat(shapeWidth * scale)
        let projectedHeight = CGFloat(shapeHeight * scale)
        let offsetX = rect.minX + padding + (availableWidth - projectedWidth) / 2
        let offsetY = rect.minY + padding + (availableHeight - projectedHeight) / 2

        return flatPoints.map { point in
            let x = offsetX + CGFloat((point.x - minX) * scale)
            // Screen Y grows downward; north (larger latitude) must render upward.
            let y = offsetY + (projectedHeight - CGFloat((point.y - minY) * scale))
            return CGPoint(x: x, y: y)
        }
    }
}
