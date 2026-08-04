//
//  Colors.swift
//  fastAndCar
//
//  Core palette and the speed → color heatmap ramp used throughout the app.
//

import SwiftUI
import UIKit

enum AppColor {
    static let background = Color(hex: 0x000000)
    static let surface = Color(hex: 0x0A0A0A)
    static let surfaceElevated = Color(hex: 0x151515)
    static let textPrimary = Color(hex: 0xFFFFFF)
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.38)
    static let accent = Color(hex: 0x00E676)

    static let glassBorder = Color.white.opacity(0.12)
    static let glassBorderSubtle = Color.white.opacity(0.06)

    static let routeStart = Color(hex: 0x00E676)
    static let routeEnd = Color(hex: 0xFF3B30)

    /// Speed heatmap stops: (km/h threshold, color). Matches the product spec's
    /// 0-20 / 20-50 / 50-90 / 90-130 / 130+ bands, but colors are blended
    /// continuously between stops rather than stepped.
    static let heatmapStops: [(speedKph: Double, color: Color)] = [
        (0, Color(hex: 0x2E86FF)),
        (20, Color(hex: 0x00E676)),
        (50, Color(hex: 0xFFD600)),
        (90, Color(hex: 0xFF9100)),
        (130, Color(hex: 0xFF3B30)),
    ]

    /// Continuous speed → color interpolation for the route heatmap.
    static func heatmapColor(forSpeedKph speed: Double) -> Color {
        let stops = heatmapStops
        guard let first = stops.first, let last = stops.last else { return accent }
        if speed <= first.speedKph { return first.color }
        if speed >= last.speedKph { return last.color }

        for i in 0..<(stops.count - 1) {
            let lower = stops[i]
            let upper = stops[i + 1]
            if speed >= lower.speedKph && speed <= upper.speedKph {
                let range = upper.speedKph - lower.speedKph
                let t = range > 0 ? (speed - lower.speedKph) / range : 0
                return lower.color.blended(with: upper.color, fraction: t)
            }
        }
        return last.color
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex & 0xFF0000) >> 16) / 255.0
        let g = Double((hex & 0x00FF00) >> 8) / 255.0
        let b = Double(hex & 0x0000FF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    /// Linear RGB blend toward another color. Used for smooth heatmap gradients.
    func blended(with other: Color, fraction: Double) -> Color {
        let t = min(max(fraction, 0), 1)
        let a = self.resolveComponents()
        let b = other.resolveComponents()
        return Color(
            .sRGB,
            red: a.r + (b.r - a.r) * t,
            green: a.g + (b.g - a.g) * t,
            blue: a.b + (b.b - a.b) * t,
            opacity: a.a + (b.a - a.a) * t
        )
    }

    private func resolveComponents() -> (r: Double, g: Double, b: Double, a: Double) {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }
}
