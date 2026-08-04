//
//  RouteMotifShape.swift
//  fastAndCar
//
//  A purely decorative angular route line — the same "F1 track map" language
//  used for real trips, used here for onboarding/empty-state wow moments.
//

import SwiftUI

struct RouteMotifShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()

        path.move(to: CGPoint(x: w * 0.06, y: h * 0.78))
        path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.78))
        path.addCurve(
            to: CGPoint(x: w * 0.56, y: h * 0.58),
            control1: CGPoint(x: w * 0.50, y: h * 0.78),
            control2: CGPoint(x: w * 0.56, y: h * 0.70)
        )
        path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.40))
        path.addCurve(
            to: CGPoint(x: w * 0.74, y: h * 0.22),
            control1: CGPoint(x: w * 0.56, y: h * 0.26),
            control2: CGPoint(x: w * 0.62, y: h * 0.22)
        )
        path.addLine(to: CGPoint(x: w * 0.94, y: h * 0.22))

        return path
    }

    /// Normalized (0...1) start/end points, matching the geometry above —
    /// used to place the glowing start/end dots without re-deriving them.
    static let startPointUnit = CGPoint(x: 0.06, y: 0.78)
    static let endPointUnit = CGPoint(x: 0.94, y: 0.22)
}
