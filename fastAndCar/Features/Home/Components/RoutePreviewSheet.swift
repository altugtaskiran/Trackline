//
//  RoutePreviewSheet.swift
//  fastAndCar
//
//  Opened by tapping a route line on the Home map's discovery layer
//  (RouteDiscoveryOverlay, drawn inside LiveRouteMapView) — a half-height
//  preview so picking a nearby route never requires leaving Ana Sayfa for
//  the Global Rotalar tab.
//

import CoreLocation
import SwiftUI

struct RoutePreviewSheet: View {
    let segment: Segment
    var onFollow: (Segment) -> Void
    var onDismiss: () -> Void
    /// Pushes the full SegmentDetailView (real leaderboard, all efforts) —
    /// this sheet only ever shows the top 3.
    var onShowLeaderboard: (Segment) -> Void = { _ in }

    @State private var startPlaceName: String?
    @State private var endPlaceName: String?
    @State private var topEfforts: [SegmentEffort] = []
    @State private var isLoadingLeaderboard = true
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(segment.name)
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("\(String.appLocalized("Oluşturan")): \(segment.creatorNickname)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AppColor.textTertiary)
                }
            }

            HStack(spacing: 12) {
                statTile(title: "Mesafe", value: distanceUnit.distanceString(meters: segment.lengthMeters), icon: "point.topleft.down.curvedto.point.bottomright.up")
                statTile(title: "Tahmini Süre", value: formatDuration(segment.creatorDurationSeconds), icon: "stopwatch.fill")
                statTile(title: "Beğeni", value: "\(segment.voteCount)", icon: "hand.thumbsup.fill")
            }

            if startPlaceName != nil || endPlaceName != nil {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(AppColor.textTertiary)
                    Text("\(startPlaceName ?? "?") → \(endPlaceName ?? "?")")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
            }

            leaderboardPreview

            Button {
                onFollow(segment)
            } label: {
                Label("Bu Rotayı Sür", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
            }
            .buttonStyle(.glass(.accent))
        }
        .padding(20)
        .task(id: segment.id) {
            startPlaceName = nil
            endPlaceName = nil
            guard let start = segment.startCoordinate, let end = segment.endCoordinate else { return }
            async let startName = PlaceNameResolver.resolve(coordinate: start)
            async let endName = PlaceNameResolver.resolve(coordinate: end)
            startPlaceName = await startName
            endPlaceName = await endName
        }
        .task(id: segment.id) {
            isLoadingLeaderboard = true
            topEfforts = (try? await CloudKitSegmentService.fetchLeaderboard(segmentId: segment.id)) ?? []
            isLoadingLeaderboard = false
        }
    }

    @ViewBuilder
    private var leaderboardPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Liderlik Tablosu")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                if !isLoadingLeaderboard {
                    Text("\(topEfforts.count) \(String.appLocalized("kişi sürdü"))")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            if isLoadingLeaderboard {
                ProgressView().tint(AppColor.accent)
            } else if topEfforts.isEmpty {
                Text("Bu rotayı henüz kimse sürmedi — ilk sen ol.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(topEfforts.prefix(3).enumerated()), id: \.element.id) { index, effort in
                        HStack(spacing: 10) {
                            Text("#\(index + 1)")
                                .font(AppFont.caption.weight(.bold))
                                .foregroundStyle(AppColor.accent)
                                .frame(width: 22, alignment: .leading)
                            Text(effort.nickname)
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(formatDuration(effort.durationSeconds))
                                .font(AppFont.statValue(14))
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                }

                Button {
                    onShowLeaderboard(segment)
                } label: {
                    Text("Tam Liderlik Tablosunu Gör")
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColor.accent)
                }
            }
        }
        .glassCard(cornerRadius: 16, padding: 14)
    }

    private func statTile(title: LocalizedStringKey, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColor.accent)
            Text(value)
                .font(AppFont.statValue(15))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16, padding: 12)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
