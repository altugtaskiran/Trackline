//
//  TripDetailView.swift
//  fastAndCar
//
//  The centerpiece screen: F1-style route, speed heatmap, playback, driving
//  score, stat grid, and an editable timeline.
//

import MapKit
import SwiftUI

struct TripDetailView: View {
    @State private var viewModel: TripDetailViewModel
    @State private var showsShareSheet = false
    @State private var showsCreateSegment = false
    @State private var mapReadyRetryTick = 0
    @Environment(\.locale) private var locale
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault }

    init(trip: Trip) {
        _viewModel = State(initialValue: TripDetailViewModel(trip: trip))
    }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    routeHero
                    PlaybackBar(viewModel: viewModel)
                    DrivingScoreCard(score: viewModel.score)
                    SpeedDistributionView(samples: viewModel.samples)
                    StatTileGrid(stats: viewModel.stats)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Timeline")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                            .padding(.bottom, 8)
                        TimelineList(trip: viewModel.trip, stopEvents: viewModel.stopEvents) { id, label in
                            viewModel.renameStopEvent(id: id, label: label)
                        }
                    }
                    .glassCard(cornerRadius: 22, padding: 18)
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.trip.routeTitle)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            // Adjacent .topBarTrailing items still merge into one shared
            // glass capsule on their own — separate ToolbarItems alone
            // don't break that grouping, a ToolbarSpacer in between does,
            // giving Share and Segment their own distinct circles. Share
            // comes first (camera icon — it produces a photo card) with
            // Segment second (a route/navigation icon — it turns this trip
            // into a followable route), swapped from the old ruler/share
            // ordering which read backwards for what each button actually does.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsShareSheet = true
                } label: {
                    Image(systemName: "camera.fill")
                        .foregroundStyle(AppColor.accent)
                }
            }
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsCreateSegment = true
                } label: {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .foregroundStyle(AppColor.accent)
                }
            }
        }
        .sheet(isPresented: $showsShareSheet) {
            ShareCardView(trip: viewModel.trip)
        }
        .sheet(isPresented: $showsCreateSegment) {
            CreateSegmentFlowView(trip: viewModel.trip)
        }
        #if DEBUG
        .task {
            // Test-only hook: launching with -uiTestAutoShare opens the
            // share sheet automatically once Trip Detail appears.
            guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoShare") else { return }
            try? await Task.sleep(for: .seconds(1))
            showsShareSheet = true
        }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoPlay") else { return }
            try? await Task.sleep(for: .seconds(1))
            viewModel.play()
        }
        #endif
    }

    // Was RouteMapBackdrop + GeoMapProjector's linear equirectangular
    // approximation — the same class of drift bug fixed everywhere else
    // this session (SegmentDetailView, CreateSegmentFlowView,
    // CrewSegmentDetailView, LiveRouteMapView): over a long/wide enough
    // route, the approximation diverges from MapKit's real projection and
    // the line visibly slides off the streets underneath. This screen
    // couldn't just switch to native MapPolyline like those did, because
    // the heatmap coloring and RouteInspectorOverlay's tap-to-inspect both
    // depend on screen-space Canvas drawing — but MapReader's own
    // proxy.convert is the exact live projection the Map is actually
    // using (no approximation to drift), so swapping the projector
    // closure's implementation keeps all of that working while fixing
    // the drift.
    private var routeHero: some View {
        MapReader { mapProxy in
            GeometryReader { geoProxy in
                let rect = CGRect(origin: .zero, size: geoProxy.size)
                let region = FittedRegion.fitting(samples: viewModel.samples, aspectRatio: rect.width / max(rect.height, 1))
                let projector: ([LocationSample], CGRect, CGFloat) -> [CGPoint] = { samples, rect, _ in
                    samples.map { mapProxy.convert($0.coordinate, to: .local) ?? CGPoint(x: rect.midX, y: rect.midY) }
                }

                ZStack {
                    Map(initialPosition: .region(region), interactionModes: []) {}
                        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                        .environment(\.colorScheme, .light)
                        .opacity(0.6)

                    // mapProxy.convert can return nil for every point on
                    // the very first render — the Map underneath hasn't
                    // finished establishing its projection yet (this is
                    // a plain one-shot Canvas, not a continuously
                    // redrawing one, so it never got a second chance to
                    // retry) — which the fallback above quietly draws as
                    // every point stacked at the view's center: no visible
                    // line at all (confirmed live: "map boş gözüküyor, bir
                    // kere dokunmam gerekiyor" — any unrelated state change
                    // forcing a redraw happened to fix it, by which point
                    // the map was ready). Forcing a few extra redraws
                    // shortly after appear self-corrects once the map's
                    // actually ready, with no user interaction needed.
                    Group {
                        RouteCanvas(samples: viewModel.samples, lineWidth: 3, showsEndpoints: true, padding: 24, projector: projector)
                        RouteEndpointLabels(
                            samples: viewModel.samples,
                            startPlaceName: viewModel.trip.startPlaceName,
                            endPlaceName: viewModel.trip.endPlaceName,
                            padding: 24,
                            projector: projector
                        )
                        RouteInspectorOverlay(samples: viewModel.samples, padding: 24, inspectedIndex: $viewModel.inspectedIndex, projector: projector)
                    }
                    .id(mapReadyRetryTick)

                    if let sample = viewModel.inspectedSample {
                        VStack {
                            inspectorTooltip(for: sample)
                            Spacer()
                        }
                    }
                }
            }
        }
        .task {
            for _ in 0..<5 {
                try? await Task.sleep(for: .milliseconds(100))
                mapReadyRetryTick += 1
            }
        }
        .frame(height: 320)
        .glassCard(cornerRadius: 26, padding: 0)
    }

    private func inspectorTooltip(for sample: LocationSample) -> some View {
        HStack(spacing: 10) {
            Text(sample.timestamp.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(locale)))
                .font(AppFont.caption.bold())
                .foregroundStyle(AppColor.textPrimary)
            Text(distanceUnit.speedString(kph: sample.speedKph))
                .font(AppFont.caption.bold())
                .foregroundStyle(AppColor.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(.ultraThinMaterial))
        .padding(12)
    }
}
