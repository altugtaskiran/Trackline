//
//  DrivingScoreCard.swift
//  fastAndCar
//

import SwiftUI

struct DrivingScoreCard: View {
    let score: DrivingScore

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(AppColor.glassBorder, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(score.value) / 100)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.9, dampingFraction: 0.85), value: score.value)

                VStack(spacing: 0) {
                    Text("\(score.value)")
                        .font(AppFont.statValue(26))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("/100")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 6) {
                Text("Driving Score")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                ForEach(score.insights, id: \.self) { insight in
                    Text("• \(insight)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            Spacer(minLength: 0)
        }
        .glassCard(cornerRadius: 22, padding: 18)
    }

    private var ringColor: Color {
        switch score.value {
        case 85...: AppColor.accent
        case 60..<85: Color(hex: 0xFFD600)
        default: Color(hex: 0xFF3B30)
        }
    }
}
