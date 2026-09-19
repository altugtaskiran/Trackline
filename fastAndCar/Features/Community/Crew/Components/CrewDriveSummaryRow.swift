//
//  CrewDriveSummaryRow.swift
//  fastAndCar
//

import SwiftUI

struct CrewDriveSummaryRow: View {
    let summary: CrewDriveSummary
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(AppColor.accent.opacity(0.16))
                Text(String(summary.drivingScore))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.accent)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.nickname)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("\(distanceUnit.distanceString(meters: summary.distanceMeters)) · Ort. \(distanceUnit.speedString(kph: summary.averageSpeedKph))")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            Text(distanceUnit.speedString(kph: summary.topSpeedKph))
                .font(AppFont.statValue(16))
                .foregroundStyle(AppColor.accent)
        }
        .glassCard(cornerRadius: 18, padding: 14)
    }
}
