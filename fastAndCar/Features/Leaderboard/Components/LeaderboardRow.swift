//
//  LeaderboardRow.swift
//  fastAndCar
//

import SwiftUI

struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry

    var body: some View {
        HStack(spacing: 14) {
            Text("#\(rank)")
                .font(AppFont.statValue(16))
                .foregroundStyle(rank == 1 ? AppColor.accent : AppColor.textSecondary)
                .frame(width: 30, alignment: .leading)

            miniRoute
                .frame(width: 56, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.nickname)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(String(format: "%.1f km · %@", entry.distanceMeters / 1000, formatDuration(entry.driveTime)))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            Text(String(format: "%.0f km/h", entry.topSpeedKph))
                .font(AppFont.statValue(18))
                .foregroundStyle(AppColor.accent)
        }
        .glassCard(cornerRadius: 18, padding: 14)
    }

    private var miniRoute: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let points = projectedPoints(in: rect)
            guard points.count > 1 else { return }
            var path = Path()
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            context.stroke(path, with: .color(AppColor.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    private func projectedPoints(in rect: CGRect) -> [CGPoint] {
        guard let origin = entry.polyline.first, !entry.polyline.isEmpty else { return [] }
        let meanLatitude = entry.polyline.reduce(0.0) { $0 + $1.lat } / Double(entry.polyline.count)
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = 111_320.0 * cos(meanLatitude * .pi / 180)

        let flat = entry.polyline.map { point -> (x: Double, y: Double) in
            let x = (point.lon - origin.lon) * metersPerDegreeLongitude
            let y = (point.lat - origin.lat) * metersPerDegreeLatitude
            return (x, y)
        }

        let xs = flat.map(\.x)
        let ys = flat.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return [] }

        let width = maxX - minX
        let height = maxY - minY
        let scaleX = width > 0 ? Double(rect.width) / width : .infinity
        let scaleY = height > 0 ? Double(rect.height) / height : .infinity
        var scale = min(scaleX, scaleY)
        if !scale.isFinite { scale = [scaleX, scaleY].first(where: \.isFinite) ?? 1 }

        let projectedWidth = CGFloat(width * scale)
        let projectedHeight = CGFloat(height * scale)
        let offsetX = (rect.width - projectedWidth) / 2
        let offsetY = (rect.height - projectedHeight) / 2

        return flat.map { point in
            CGPoint(
                x: offsetX + CGFloat((point.x - minX) * scale),
                y: offsetY + (projectedHeight - CGFloat((point.y - minY) * scale))
            )
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        return "\(minutes)m"
    }
}
