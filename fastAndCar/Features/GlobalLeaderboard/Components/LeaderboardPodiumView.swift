//
//  LeaderboardPodiumView.swift
//  fastAndCar
//
//  Just FlameGlow now — the side-by-side 1st/2nd/3rd podium layout this
//  file used to hold read as confusing/random rather than clearly ranked
//  (two circles next to each other don't obviously say "this one's #1"),
//  so the leaderboard went back to a plain top-to-bottom list
//  (SegmentEffortRow) for every rank, with just the #1 row keeping this
//  glow behind its avatar.
//

import SwiftUI

/// Layered, softly pulsing flame — a couple of blurred `flame.fill` symbols
/// in a warm gradient behind an avatar, plus a matching radial glow ring.
/// `scale` lets callers size it down for tighter row layouts.
struct FlameGlow: View {
    var scale: CGFloat = 1.0
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0xFF9F0A).opacity(0.45), .clear],
                        center: .center, startRadius: 0, endRadius: 60 * scale
                    )
                )
                .frame(width: 120 * scale, height: 120 * scale)
                .blur(radius: 8)
                .scaleEffect(pulse ? 1.08 : 0.94)

            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "flame.fill")
                    .font(.system(size: 30 * scale))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: 0xFFD60A), Color(hex: 0xFF453A)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .rotationEffect(.degrees(Double(index - 1) * 26))
                    .offset(x: CGFloat(index - 1) * 14 * scale, y: 10 * scale)
                    .opacity(0.85)
                    .blur(radius: 1.5)
            }
        }
        .scaleEffect(pulse ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
        .allowsHitTesting(false)
    }
}
