//
//  SegmentRow.swift
//  fastAndCar
//

import SwiftUI

struct SegmentRow: View {
    let name: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(AppColor.accent.opacity(0.16))
                Image(systemName: "ruler")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
        }
        .glassCard(cornerRadius: 18, padding: 14)
    }
}
