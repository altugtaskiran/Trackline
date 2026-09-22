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

    @State private var startPlaceName: String?
    @State private var endPlaceName: String?
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
