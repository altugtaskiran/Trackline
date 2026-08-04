//
//  PlaybackBar.swift
//  fastAndCar
//
//  Play/pause + scrubber, with live speed/distance/time readouts. Scrubbing
//  the slider in either direction covers "ileri-geri sarma" (seek).
//

import SwiftUI

struct PlaybackBar: View {
    var viewModel: TripDetailViewModel

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                LiveStatBadge(title: "Hız", value: String(format: "%.0f km/h", viewModel.playbackSample?.speedKph ?? 0))
                LiveStatBadge(title: "Mesafe", value: String(format: "%.1f km", viewModel.playbackDistanceMeters / 1000))
                LiveStatBadge(title: "Süre", value: formatted(viewModel.playbackElapsed))
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 14) {
                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppColor.background)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(AppColor.accent))
                }

                Slider(
                    value: Binding(
                        get: { viewModel.playbackProgress },
                        set: { viewModel.seek(toProgress: $0) }
                    )
                )
                .tint(AppColor.accent)
            }
        }
        .glassCard(cornerRadius: 22, padding: 18)
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
