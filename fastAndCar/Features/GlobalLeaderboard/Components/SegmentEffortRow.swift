//
//  SegmentEffortRow.swift
//  fastAndCar
//

import SwiftUI

struct SegmentEffortRow: View {
    let rank: Int
    let effort: SegmentEffort
    var isCurrentUser: Bool = false
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault }

    var body: some View {
        HStack(spacing: 14) {
            Text("#\(rank)")
                .font(AppFont.statValue(16))
                .foregroundStyle(rank == 1 ? AppColor.accent : AppColor.textSecondary)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(effort.nickname)
                    .font(AppFont.headline)
                    .foregroundStyle(isCurrentUser ? AppColor.accent : AppColor.textPrimary)
                Text("Ort. \(distanceUnit.speedString(kph: effort.averageSpeedKph)) · Zirve \(distanceUnit.speedString(kph: effort.topSpeedKph))")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            Text(formatDuration(effort.durationSeconds))
                .font(AppFont.statValue(18))
                .foregroundStyle(AppColor.accent)
        }
        .glassCard(cornerRadius: 18, padding: 14)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
