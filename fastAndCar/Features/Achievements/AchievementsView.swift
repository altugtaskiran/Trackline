//
//  AchievementsView.swift
//  fastAndCar
//
//  Faz 4 — the badge grid. Reads the same @Query'd trips TripsListView
//  already has and runs AchievementEvaluator fresh on appear, so this is
//  always in sync with whatever's actually in the trip history — no
//  separate "unlocked" state of its own to drift out of date.
//

import SwiftData
import SwiftUI

struct AchievementsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]

    private var unlockedIds: Set<String> {
        AchievementEvaluator.unlockedIds(for: trips)
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(format: String.appLocalized("%d / %d rozet"), unlockedIds.count, AchievementCatalog.all.count))
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(AchievementCatalog.all) { achievement in
                                AchievementTile(achievement: achievement, isUnlocked: unlockedIds.contains(achievement.id))
                            }
                        }
                        .padding(.top, 12)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Başarılar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct AchievementTile: View {
    let achievement: Achievement
    let isUnlocked: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(isUnlocked ? AppColor.accent.opacity(0.18) : AppColor.surfaceElevated)
                Image(systemName: isUnlocked ? achievement.icon : "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isUnlocked ? AppColor.accent : AppColor.textTertiary)
            }
            .frame(width: 52, height: 52)

            // achievement.title/subtitle are fixed Turkish source strings
            // from AchievementCatalog — routed through LocalizedStringKey
            // (not plain string interpolation) so they look themselves up
            // in the String Catalog instead of rendering verbatim, same
            // pattern DrivingScoreCard uses for its dynamic insight text.
            Text(LocalizedStringKey(achievement.title))
                .font(AppFont.statLabel)
                .foregroundStyle(isUnlocked ? AppColor.textPrimary : AppColor.textTertiary)
                .multilineTextAlignment(.center)

            Text(LocalizedStringKey(achievement.subtitle))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 10)
        .glassCard(cornerRadius: 18, padding: 0)
        .opacity(isUnlocked ? 1 : 0.6)
    }
}
