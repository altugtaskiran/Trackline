//
//  Typography.swift
//  fastAndCar
//
//  Rounded, numeral-forward type scale for a premium sports-dashboard feel.
//

import SwiftUI

enum AppFont {
    /// Huge live/hero numerals (e.g. live speed, driving score).
    static func hero(_ size: CGFloat = 96) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    /// Stat tile numerals.
    static func statValue(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static let statLabel = Font.system(size: 12, weight: .medium, design: .rounded)

    static let title = Font.system(size: 22, weight: .bold, design: .rounded)
    static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 15, weight: .regular, design: .rounded)
    static let caption = Font.system(size: 13, weight: .medium, design: .rounded)
    static let button = Font.system(size: 16, weight: .semibold, design: .rounded)
}

extension View {
    /// Slightly tightened tracking for large rounded numerals, matching Apple's
    /// dashboard-style stat displays.
    func numeralTracking() -> some View {
        tracking(-0.5)
    }
}
