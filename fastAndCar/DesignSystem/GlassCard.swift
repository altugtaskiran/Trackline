//
//  GlassCard.swift
//  fastAndCar
//
//  Reusable glassmorphism container used across every screen.
//

import SwiftUI

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppColor.glassBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
    }
}

extension View {
    /// Wraps this view in the standard app glass-card chrome.
    func glassCard(cornerRadius: CGFloat = 24, padding: CGFloat = 16) -> some View {
        GlassCard(cornerRadius: cornerRadius, padding: padding) { self }
    }
}
