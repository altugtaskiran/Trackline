//
//  TripDetailView.swift
//  fastAndCar
//
//  The centerpiece screen: F1-style route, speed heatmap, playback, driving
//  score, stat grid, and an editable timeline.
//

import SwiftUI

struct TripDetailView: View {
    @State private var viewModel: TripDetailViewModel
    @State private var showsShareSheet = false
    @State private var showsCreateSegment = false
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

    private var routeHero: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            let region = FittedRegion.fitting(samples: viewModel.samples, aspectRatio: rect.width / max(rect.height, 1))
            let projector = GeoMapProjector.projector(region: region)

            ZStack {
                RouteMapBackdrop(region: region)
                RouteCanvas(samples: viewModel.samples, lineWidth: 3, showsEndpoints: true, padding: 24, projector: projector)
                RouteEndpointLabels(
                    samples: viewModel.samples,
                    startPlaceName: viewModel.trip.startPlaceName,
                    endPlaceName: viewModel.trip.endPlaceName,
                    padding: 24,
                    projector: projector
                )
                RouteInspectorOverlay(samples: viewModel.samples, padding: 24, inspectedIndex: $viewModel.inspectedIndex, projector: projector)

                if let sample = viewModel.inspectedSample {
                    VStack {
                        inspectorTooltip(for: sample)
                        Spacer()
                    }
                }
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
