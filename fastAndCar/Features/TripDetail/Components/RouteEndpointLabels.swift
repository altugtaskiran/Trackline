//
//  RouteEndpointLabels.swift
//  fastAndCar
//
//  Place-name tags floating above RouteCanvas's start/end dots. Uses the same
//  RouteProjector math as RouteCanvas and RouteInspectorOverlay so a tag
//  always sits directly over its dot, whatever shape the route was fit into.
//

import SwiftUI

struct RouteEndpointLabels: View {
    let samples: [LocationSample]
    let startPlaceName: String?
    let endPlaceName: String?
    let padding: CGFloat
    var projector: ([LocationSample], CGRect, CGFloat) -> [CGPoint] = RouteProjector.project

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            let points = projector(samples, rect, padding)

            ZStack {
                if let startPlaceName, let first = points.first {
                    tag(startPlaceName, color: AppColor.routeStart)
                        .position(clamped(first, in: rect))
                }

                if points.count > 1, let endPlaceName, let last = points.last {
                    tag(endPlaceName, color: AppColor.routeEnd)
                        .position(clamped(last, in: rect))
                }
            }
            .allowsHitTesting(false)
        }
    }

    private let labelHalfWidth: CGFloat = 78
    private let verticalOffset: CGFloat = 22

    private func tag(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(AppFont.caption.bold())
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.ultraThinMaterial))
        .frame(maxWidth: labelHalfWidth * 2)
    }

    private func clamped(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        let x = min(max(point.x, rect.minX + padding + labelHalfWidth), rect.maxX - padding - labelHalfWidth)
        let y = max(point.y - verticalOffset, rect.minY + padding + 12)
        return CGPoint(x: x, y: y)
    }
}
