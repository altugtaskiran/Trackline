//
//  ShareCardRenderer.swift
//  fastAndCar
//
//  Rasterizes a fixed premium share card (route + key stats) into a UIImage
//  via ImageRenderer, ready for the native share sheet — covers Instagram
//  Stories/Twitter/WhatsApp/iMessage without any per-platform SDK.
//
//  Two layouts: a full-bleed card over the user's own car photo (from
//  Garage) when one exists, with the route drawn straight across it, or the
//  original plain black card as a fallback when there's no car photo yet.
//

import SwiftUI

private struct ShareCardContent: View {
    let trip: Trip
    let carPhotoData: Data?

    private var carImage: UIImage? {
        carPhotoData.flatMap { UIImage(data: $0) }
    }

    var body: some View {
        if let carImage {
            photoCard(carImage: carImage)
        } else {
            plainCard
        }
    }

    private func photoCard(carImage: UIImage) -> some View {
        ZStack {
            Image(uiImage: carImage)
                .resizable()
                .scaledToFill()
                .frame(width: 360, height: 640)
                .clipped()

            LinearGradient(
                colors: [
                    .black.opacity(0.6), .black.opacity(0.05), .black.opacity(0.05), .black.opacity(0.8),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Header pinned to the top.
            VStack(spacing: 0) {
                HStack {
                    Text("Trackline")
                        .font(AppFont.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text(trip.startTime.formatted(date: .abbreviated, time: .omitted))
                        .font(AppFont.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.top, 22)
                .padding(.horizontal, 24)
                Spacer()
            }

            // A direct ZStack child centers by default — dead center of the
            // 360x640 card regardless of how tall the header/stats blocks
            // end up being.
            RouteCanvas(samples: trip.samples, lineWidth: 5, showsEndpoints: true, padding: 10)
                .frame(width: 300, height: 200)

            // Stats pinned to the bottom.
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 12) {
                    HStack {
                        shareStat(title: "TOP SPEED", value: String(format: "%.0f km/h", trip.topSpeedKph), tint: .white)
                        Spacer()
                        shareStat(title: "AVG SPEED", value: String(format: "%.0f km/h", trip.averageSpeedKph), tint: .white)
                    }
                    HStack {
                        shareStat(title: "DISTANCE", value: String(format: "%.1f km", trip.distanceMeters / 1000), tint: .white)
                        Spacer()
                        shareStat(title: "DRIVE TIME", value: formatDuration(trip.driveTime), tint: .white)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 26)
            }
        }
        .frame(width: 360, height: 640)
    }

    // Same fixed 360x640 canvas and centered-route structure as photoCard
    // (just without the photo/scrim layers) — every rendered card shares
    // one true aspect ratio, so the preview screen's fit math never has to
    // guess which layout produced the image.
    private var plainCard: some View {
        ZStack {
            AppColor.background

            VStack(spacing: 0) {
                HStack {
                    Text("Trackline")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text(trip.startTime.formatted(date: .abbreviated, time: .omitted))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .padding(.top, 22)
                .padding(.horizontal, 24)
                Spacer()
            }

            RouteCanvas(samples: trip.samples, lineWidth: 4, showsEndpoints: true, padding: 12)
                .frame(width: 300, height: 220)

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 12) {
                    HStack {
                        shareStat(title: "TOP SPEED", value: String(format: "%.0f km/h", trip.topSpeedKph))
                        Spacer()
                        shareStat(title: "AVG SPEED", value: String(format: "%.0f km/h", trip.averageSpeedKph))
                    }
                    HStack {
                        shareStat(title: "DISTANCE", value: String(format: "%.1f km", trip.distanceMeters / 1000))
                        Spacer()
                        shareStat(title: "DRIVE TIME", value: formatDuration(trip.driveTime))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 26)
            }
        }
        .frame(width: 360, height: 640)
    }

    private func shareStat(title: String, value: String, tint: Color = AppColor.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(tint.opacity(0.65))
            Text(value)
                .font(AppFont.statValue(20))
                .foregroundStyle(tint)
        }
        .frame(minWidth: 140, alignment: .leading)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

enum ShareCardRenderer {
    @MainActor
    static func render(trip: Trip, carPhotoData: Data?) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardContent(trip: trip, carPhotoData: carPhotoData))
        // Fixed high-density scale for crisp shares regardless of the
        // rendering device's own screen (this view is never actually shown
        // on-screen at 1x).
        renderer.scale = 3.0
        return renderer.uiImage
    }
}
