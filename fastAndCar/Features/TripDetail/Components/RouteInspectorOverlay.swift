//
//  RouteInspectorOverlay.swift
//  fastAndCar
//
//  Transparent hit-testing layer over the route hero: tap anywhere on the
//  line to find the nearest recorded sample and report it back via binding.
//  Uses the same RouteProjector math as RouteCanvas so the marker always
//  lands exactly on the visible line. A tap (not a drag) so it doesn't
//  fight the map underneath for pan/zoom gestures.
//

import SwiftUI

struct RouteInspectorOverlay: View {
    let samples: [LocationSample]
    let padding: CGFloat
    @Binding var inspectedIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            let points = RouteProjector.project(samples: samples, into: rect, padding: padding)

            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                inspectedIndex = nearestIndex(to: value.location, in: points)
                            }
                    )

                if let inspectedIndex, points.indices.contains(inspectedIndex) {
                    Circle()
                        .fill(AppColor.textPrimary)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(AppColor.background, lineWidth: 2))
                        .position(points[inspectedIndex])
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func nearestIndex(to location: CGPoint, in points: [CGPoint]) -> Int? {
        guard !points.isEmpty else { return nil }
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, point) in points.enumerated() {
            let dx = point.x - location.x
            let dy = point.y - location.y
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }
}
