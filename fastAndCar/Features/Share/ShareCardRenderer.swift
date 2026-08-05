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

/// Ember-glow palette for the "just raced, engine still hot" treatment —
/// warmer and more saturated than the app's everyday accent so the share
/// card reads as a trophy moment rather than another dashboard screen.
private enum HeatColor {
    static let ember = Color(hex: 0xFF3B00)
    static let amber = Color(hex: 0xFF9100)
    static let redline = Color(hex: 0xFF3B30)
    static let yellow = Color(hex: 0xFFD600)
    static let fireGradient = LinearGradient(
        colors: [yellow, amber, redline],
        startPoint: .leading,
        endPoint: .trailing
    )
}

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
                    .black.opacity(0.6), .black.opacity(0.05), .black.opacity(0.05), .black.opacity(0.85),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            emberGlow

            header

            routeWithHeatTrail(lineWidth: 5, padding: 10)
                .frame(width: 300, height: 200)

            VStack(spacing: 0) {
                Spacer()
                statsBlock
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

            emberGlow

            header

            routeWithHeatTrail(lineWidth: 4, padding: 12)
                .frame(width: 300, height: 220)

            VStack(spacing: 0) {
                Spacer()
                statsBlock
                    .padding(.horizontal, 24)
                    .padding(.bottom, 26)
            }
        }
        .frame(width: 360, height: 640)
    }

    /// Wordmark + a small pulsing redline dot (an idle warning-light cue)
    /// and a "SESSION COMPLETE" tag — the cooled-down, just-finished-racing
    /// beat the card is going for, spelled out rather than just implied by color.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(HeatColor.redline)
                        .frame(width: 7, height: 7)
                        .shadow(color: HeatColor.redline, radius: 5)
                    Text("TRACKLINE")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .italic()
                        .tracking(1.4)
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(trip.startTime.formatted(date: .abbreviated, time: .omitted))
                    .font(AppFont.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Text("SESSION COMPLETE")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(HeatColor.amber.opacity(0.85))
        }
        .padding(.top, 22)
        .padding(.horizontal, 24)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Bottom-heavy radial warmth, like heat still radiating off a grille
    /// after a hard drive — screen-blended so it lifts the blacks instead of
    /// flattening them.
    private var emberGlow: some View {
        ZStack {
            RadialGradient(
                colors: [HeatColor.ember.opacity(0.5), HeatColor.ember.opacity(0)],
                center: .bottom,
                startRadius: 20,
                endRadius: 280
            )
            RadialGradient(
                colors: [HeatColor.amber.opacity(0.3), .clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 220
            )
        }
        .compositingGroup()
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    /// The route line with a soft, blurred duplicate glowing underneath it —
    /// a heat-trail rather than a plain map line.
    private func routeWithHeatTrail(lineWidth: CGFloat, padding: CGFloat) -> some View {
        ZStack {
            RouteCanvas(samples: trip.samples, lineWidth: lineWidth * 3, showsEndpoints: false, padding: padding)
                .blur(radius: 12)
                .opacity(0.6)
                .compositingGroup()
                .blendMode(.screen)
            RouteCanvas(samples: trip.samples, lineWidth: lineWidth, showsEndpoints: true, padding: padding)
            RouteEndpointLabels(
                samples: trip.samples,
                startPlaceName: trip.startPlaceName,
                endPlaceName: trip.endPlaceName,
                padding: padding
            )
        }
    }

    private var statsBlock: some View {
        VStack(spacing: 12) {
            HStack {
                fireStat(title: "TOP SPEED", value: String(format: "%.0f km/h", trip.topSpeedKph))
                Spacer()
                shareStat(title: "AVG SPEED", value: String(format: "%.0f km/h", trip.averageSpeedKph))
            }
            HStack {
                shareStat(title: "DISTANCE", value: String(format: "%.1f km", trip.distanceMeters / 1000))
                Spacer()
                shareStat(title: "DRIVE TIME", value: formatDuration(trip.driveTime))
            }
        }
    }

    private func shareStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(minWidth: 140, alignment: .leading)
    }

    /// The hero stat — top speed rendered in a redline-gradient, italic and
    /// a size up from the rest, so the card's one big brag lands first.
    private func fireStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(HeatColor.amber.opacity(0.85))
            Text(value)
                .font(.system(size: 25, weight: .heavy, design: .rounded))
                .italic()
                .foregroundStyle(HeatColor.fireGradient)
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
