//
//  FeatureUnavailableView.swift
//  fastAndCar
//
//  One consistent "this needs CloudKit, which isn't on yet" empty state —
//  replaces the scattered "Bu özellik yakında aktif olacak" alerts that
//  used to ambush the driver on screen open, or after tapping a button
//  that could never have worked. Same visual language as the other empty
//  states (RoutesTabView.emptyState, GlobalLeaderboardListView's), just
//  reused instead of redrawn per screen.
//

import SwiftUI

struct FeatureUnavailableView: View {
    var title: String = "Çevrimiçi Özellik"
    var message: String = "Bu özellik yakında aktif olacak."

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.textTertiary)
            Text(title)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text(message)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// A short inline note for a single disabled action (a button, not a whole
/// screen) — pairs with `.disabled(!FeatureFlags.xEnabled)` right below it.
struct FeatureUnavailableCaption: View {
    var body: some View {
        Text("Çevrimiçi özellikler yakında aktif olacak.")
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textTertiary)
            .multilineTextAlignment(.center)
    }
}
