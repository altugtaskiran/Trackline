//
//  TripRowCard.swift
//  fastAndCar
//

import SwiftUI

struct TripRowCard: View {
    let trip: Trip

    var body: some View {
        HStack(spacing: 16) {
            RouteCanvas(samples: trip.samples, lineWidth: 2, showsEndpoints: true, padding: 8)
                .frame(width: 84, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(trip.routeTitle)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text(trip.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f km", trip.distanceMeters / 1000))
                    .font(AppFont.statValue(16))
                    .foregroundStyle(AppColor.textPrimary)
                Text(String(format: "%.0f km/h", trip.topSpeedKph))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.accent)
            }
        }
        .glassCard(cornerRadius: 20, padding: 14)
    }
}
