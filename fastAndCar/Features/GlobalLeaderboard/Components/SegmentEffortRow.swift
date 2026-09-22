//
//  SegmentEffortRow.swift
//  fastAndCar
//

import SwiftUI

struct SegmentEffortRow: View {
    let rank: Int
    let effort: SegmentEffort
    var isCurrentUser: Bool = false
    var avatar: UIImage?
    @State private var showsProfile = false
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault }

    /// Gold/silver/bronze for the top 3, nil (plain) from #4 on.
    private var rankColor: Color? {
        switch rank {
        case 1: Color(hex: 0xFFD60A)
        case 2: Color(hex: 0xC0C0C8)
        case 3: Color(hex: 0xCD7F32)
        default: nil
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Text("#\(rank)")
                .font(AppFont.statValue(16))
                .foregroundStyle(rankColor ?? AppColor.textSecondary)
                .frame(width: 34, alignment: .leading)

            ZStack {
                if rank == 1 {
                    // A soft warm halo, not a literal flame shape — at
                    // list-row scale an actual flame icon just reads as a
                    // small sticker, this reads as "glowing" instead.
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: 0xFF9F0A).opacity(0.6), .clear],
                                center: .center, startRadius: 2, endRadius: 26
                            )
                        )
                        .frame(width: 52, height: 52)
                        .blur(radius: 5)
                }
                AvatarView(image: avatar, initial: effort.nickname.first, size: 36)
                    .overlay {
                        if let rankColor {
                            Circle().strokeBorder(rankColor, lineWidth: rank == 1 ? 2.5 : 2)
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Button {
                    showsProfile = true
                } label: {
                    Text(effort.nickname)
                        .font(AppFont.headline)
                        .foregroundStyle(isCurrentUser ? AppColor.accent : AppColor.textPrimary)
                }
                .buttonStyle(.plain)
                Text("\(String.appLocalized("Zirve Hız")): \(distanceUnit.speedString(kph: effort.topSpeedKph))")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            Text(formatDuration(effort.durationSeconds))
                .font(AppFont.statValue(18))
                .foregroundStyle(AppColor.accent)
        }
        .background {
            // Ambient warm glow bleeding out from behind the whole card,
            // instead of literal flame icons stuck on the corners.
            if rank == 1 {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: 0xFF9F0A).opacity(0.35))
                    .blur(radius: 18)
                    .padding(-6)
            }
        }
        .glassCard(cornerRadius: 18, padding: 14)
        .overlay {
            if rank == 1 {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color(hex: 0xFFD60A), Color(hex: 0xFF9F0A)], startPoint: .leading, endPoint: .trailing),
                        lineWidth: 1.5
                    )
            }
        }
        .sheet(isPresented: $showsProfile) {
            if isCurrentUser {
                ProfileView()
            } else {
                PublicProfileView(userId: effort.userId, nickname: effort.nickname)
            }
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
