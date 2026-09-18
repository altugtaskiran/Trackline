//
//  StatTileGrid.swift
//  fastAndCar
//

import SwiftUI

private struct StatTile: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let value: String
    let icon: String
    let tint: Color
}

struct StatTileGrid: View {
    let stats: TripStats
    // .formatted() is a plain Foundation call, not a SwiftUI-environment-
    // aware one — without reading this back explicitly, Start/Finish Time
    // would always use the device's system locale regardless of the
    // Settings > Language override.
    @Environment(\.locale) private var locale

    private var tiles: [StatTile] {
        var result: [StatTile] = []
        result.append(StatTile(title: "Top Speed", value: String(format: "%.0f km/h", stats.topSpeedKph), icon: "speedometer", tint: Color(hex: 0xFF3B30)))
        result.append(StatTile(title: "Average Speed", value: String(format: "%.0f km/h", stats.averageSpeedKph), icon: "gauge.medium", tint: Color(hex: 0xFF9100)))
        result.append(StatTile(title: "Distance", value: String(format: "%.1f km", stats.distanceMeters / 1000), icon: "point.topleft.down.curvedto.point.bottomright.up", tint: AppColor.accent))
        result.append(StatTile(title: "Drive Time", value: formatDuration(stats.driveTime), icon: "clock.fill", tint: Color(hex: 0x2E86FF)))
        result.append(StatTile(title: "Moving Time", value: formatDuration(stats.movingTime), icon: "arrow.forward.circle.fill", tint: Color(hex: 0x32ADE6)))
        result.append(StatTile(title: "Stopped Time", value: formatDuration(stats.stoppedTime), icon: "pause.circle.fill", tint: Color(hex: 0x8E8E93)))
        result.append(StatTile(title: "Max Acceleration", value: String(format: "%.2fg", stats.maxAccelerationG), icon: "arrow.up.right.circle.fill", tint: Color(hex: 0xFF9100)))
        result.append(StatTile(title: "Max Braking", value: String(format: "%.2fg", stats.maxBrakingG), icon: "arrow.down.right.circle.fill", tint: Color(hex: 0xFF3B30)))
        result.append(StatTile(title: "Highest Altitude", value: String(format: "%.0f m", stats.highestAltitude), icon: "arrow.up.to.line", tint: Color(hex: 0xBF5AF2)))
        result.append(StatTile(title: "Lowest Altitude", value: String(format: "%.0f m", stats.lowestAltitude), icon: "arrow.down.to.line", tint: Color(hex: 0x64D2FF)))
        result.append(StatTile(title: "Elevation Gain", value: String(format: "%.0f m", stats.elevationGainMeters), icon: "arrow.up.right", tint: Color(hex: 0x34C759)))
        result.append(StatTile(title: "Elevation Loss", value: String(format: "%.0f m", stats.elevationLossMeters), icon: "arrow.down.right", tint: Color(hex: 0xFF6482)))
        result.append(StatTile(title: "Steepest Climb", value: String(format: "%.0f%%", stats.steepestClimbPercent), icon: "triangle.fill", tint: Color(hex: 0x34C759)))
        result.append(StatTile(title: "Number of Stops", value: "\(stats.stopCount)", icon: "flag.fill", tint: Color(hex: 0xFFD600)))
        result.append(StatTile(title: "Harsh Braking", value: "\(stats.harshBrakeCount)", icon: "exclamationmark.brakesignal", tint: Color(hex: 0xFF3B30)))
        result.append(StatTile(title: "Harsh Acceleration", value: "\(stats.harshAccelCount)", icon: "bolt.fill", tint: Color(hex: 0xFF9100)))
        result.append(StatTile(title: "Cornering Events", value: "\(stats.corneringCount)", icon: "arrow.triangle.turn.up.right.circle.fill", tint: Color(hex: 0xBF5AF2)))
        result.append(StatTile(title: "GPS Accuracy", value: String(format: "±%.0fm", stats.averageGpsAccuracy), icon: "location.fill", tint: Color(hex: 0x8E8E93)))
        let timeStyle = Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)
        result.append(StatTile(title: "Start Time", value: stats.startTime.formatted(timeStyle), icon: "play.circle.fill", tint: AppColor.routeStart))
        result.append(StatTile(title: "Finish Time", value: stats.finishTime.formatted(timeStyle), icon: "flag.checkered", tint: AppColor.routeEnd))
        return result
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(tiles) { tile in
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle().fill(tile.tint.opacity(0.16))
                        Image(systemName: tile.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tile.tint)
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(tile.title)
                            .font(AppFont.statLabel)
                            .foregroundStyle(AppColor.textSecondary)
                        Text(tile.value)
                            .font(AppFont.statValue(18))
                            .foregroundStyle(tile.tint)
                            .numeralTracking()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 18, padding: 14)
            }
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
