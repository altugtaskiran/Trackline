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
    // .formatted() is a plain Foundation call, not a SwiftUI-environment-
    // aware one — it won't pick up the .environment(\.locale, ...) applied
    // before rendering unless we read it back out explicitly and hand it to
    // the format style ourselves.
    @Environment(\.locale) private var locale
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault }

    private var carImage: UIImage? {
        carPhotoData.flatMap { UIImage(data: $0) }
    }

    private var shortRouteLabel: String? {
        func city(_ full: String) -> String {
            full.split(separator: ",").first.map(String.init) ?? full
        }
        switch (trip.startPlaceName, trip.endPlaceName) {
        case let (start?, end?) where start == end:
            return city(start)
        case let (start?, end?):
            return "\(city(start)) → \(city(end))"
        case let (start?, nil):
            return city(start)
        case let (nil, end?):
            return city(end)
        default:
            return nil
        }
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
                Text(trip.startTime.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)))
                    .font(AppFont.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            }
            Text("SESSION COMPLETE")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundStyle(HeatColor.amber)
            // City-only, no ", Türkiye" — the full "City, Country → City,
            // Country" routeTitle used for the nav-bar title reads fine
            // there but was way too long/soft for this card's tight,
            // tracked-caps label language (SESSION COMPLETE, TOP SPEED).
            if let routeLabel = shortRouteLabel {
                Text(routeLabel.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .padding(.top, 1)
            }
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
        }
    }

    private var statsBlock: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                fireStat(title: "TOP SPEED", value: distanceUnit.speedString(kph: trip.topSpeedKph))
                    .frame(maxWidth: .infinity)
                shareStat(title: "AVG SPEED", value: distanceUnit.speedString(kph: trip.averageSpeedKph))
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 0) {
                shareStat(title: "DISTANCE", value: distanceUnit.distanceString(meters: trip.distanceMeters))
                    .frame(maxWidth: .infinity)
                shareStat(title: "DRIVE TIME", value: formatDuration(trip.driveTime))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // Centered rather than leading-aligned: with each stat now owning an
    // equal-width half of the row, centering reads as one deliberate,
    // symmetric block instead of text stranded at the left edge of empty
    // space — a small change that makes the whole card feel more designed,
    // less like a form.
    private func shareStat(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        }
    }

    /// The hero stat — top speed rendered in a redline-gradient and a size
    /// up from the rest, so the card's one big brag lands first.
    private func fireStat(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(HeatColor.amber.opacity(0.85))
            Text(value)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(HeatColor.fireGradient)
                .shadow(color: HeatColor.redline.opacity(0.6), radius: 8)
        }
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
        // ImageRenderer draws this content into a UIImage in its own
        // detached rendering pass — it never inherits the environment
        // SwiftUI applies to the app's actual window/view tree, so the
        // Settings > Language override has to be set here explicitly or
        // every share card silently falls back to whatever Bundle's default
        // resolution picks (Turkish, being the source language).
        let content = ShareCardContent(trip: trip, carPhotoData: carPhotoData)
            .environment(\.locale, AppLanguage.current.locale ?? .autoupdatingCurrent)
        let renderer = ImageRenderer(content: content)
        // Fixed high-density scale for crisp shares regardless of the
        // rendering device's own screen (this view is never actually shown
        // on-screen at 1x).
        renderer.scale = 3.0
        return renderer.uiImage
    }
}
