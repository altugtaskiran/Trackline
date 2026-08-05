//
//  LiveStatBadge.swift
//  fastAndCar
//

import SwiftUI

struct LiveStatBadge: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppFont.statValue())
                .foregroundStyle(AppColor.textPrimary)
                .numeralTracking()
            Text(title)
                .font(AppFont.statLabel)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(minWidth: 88)
    }
}
