//
//  TripRowCard.swift
//  fastAndCar
//

import SwiftUI

struct TripRowCard: View {
    let trip: Trip
    @Environment(\.locale) private var locale
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault }

    var body: some View {
        HStack(spacing: 16) {
            RouteCanvas(samples: trip.samples, lineWidth: 2, showsEndpoints: true, padding: 8)
                .frame(width: 84, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(trip.routeTitle)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text(trip.startTime.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColor.textSecondary)
                if let followedSegmentName = trip.followedSegmentName {
                    HStack(spacing: 4) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 9))
                        Text(followedSegmentName)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color(hex: 0xBF5AF2))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(distanceUnit.distanceString(meters: trip.distanceMeters))
                    .font(AppFont.statValue(16))
                    .foregroundStyle(AppColor.textPrimary)
                Text(distanceUnit.speedString(kph: trip.topSpeedKph))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.accent)
            }
        }
        .glassCard(cornerRadius: 20, padding: 14)
    }
}
