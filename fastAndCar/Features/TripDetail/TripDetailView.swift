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
    @State private var showsLeaderboard = false

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
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    if FeatureFlags.leaderboardEnabled {
                        Button {
                            showsLeaderboard = true
                        } label: {
                            Image(systemName: "flag.checkered")
                                .foregroundStyle(AppColor.accent)
                        }
                    }
                    Button {
                        showsShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(AppColor.accent)
                    }
                }
            }
        }
        .sheet(isPresented: $showsShareSheet) {
            ShareCardView(trip: viewModel.trip)
        }
        .sheet(isPresented: $showsLeaderboard) {
            LeaderboardView(trip: viewModel.trip)
        }
        #if DEBUG
        .task {
            // Test-only hook: launching with -uiTestAutoShare opens the
            // share sheet automatically once Trip Detail appears.
            guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoShare") else { return }
            try? await Task.sleep(for: .seconds(1))
            showsShareSheet = true
        }
        #endif
    }

    private var routeHero: some View {
        ZStack {
            RouteMapBackdrop(samples: viewModel.samples)
            RouteCanvas(samples: viewModel.samples, lineWidth: 3, showsEndpoints: true, padding: 24)
            RouteInspectorOverlay(samples: viewModel.samples, padding: 24, inspectedIndex: $viewModel.inspectedIndex)

            if let sample = viewModel.inspectedSample {
                VStack {
                    inspectorTooltip(for: sample)
                    Spacer()
                }
            }
        }
        .frame(height: 320)
        .glassCard(cornerRadius: 26, padding: 0)
    }

    private func inspectorTooltip(for sample: LocationSample) -> some View {
        HStack(spacing: 10) {
            Text(sample.timestamp.formatted(date: .omitted, time: .standard))
                .font(AppFont.caption.bold())
                .foregroundStyle(AppColor.textPrimary)
            Text(String(format: "%.0f km/h", sample.speedKph))
                .font(AppFont.caption.bold())
                .foregroundStyle(AppColor.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(.ultraThinMaterial))
        .padding(12)
    }
}
