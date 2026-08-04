//
//  PrimaryGlassButton.swift
//  fastAndCar
//
//  The app's single button language: a glass pill, tinted for primary/destructive intent.
//

import SwiftUI

enum GlassButtonTone {
    case accent
    case destructive
    case neutral

    var tint: Color {
        switch self {
        case .accent: AppColor.accent
        case .destructive: Color(hex: 0xFF3B30)
        case .neutral: AppColor.textPrimary
        }
    }
}

struct GlassButtonStyle: ButtonStyle {
    var tone: GlassButtonTone = .accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.button)
            .foregroundStyle(tone == .neutral ? AppColor.textPrimary : AppColor.background)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background {
                Capsule()
                    .fill(tone == .neutral ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(tone.tint))
            }
            .overlay {
                Capsule().strokeBorder(AppColor.glassBorder, lineWidth: tone == .neutral ? 1 : 0)
            }
            .shadow(color: tone.tint.opacity(configuration.isPressed ? 0.15 : 0.35), radius: 16, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static func glass(_ tone: GlassButtonTone = .accent) -> GlassButtonStyle {
        GlassButtonStyle(tone: tone)
    }
}
