//
//  AppRootView.swift
//  fastAndCar
//
//  Routes Onboarding vs Home, hosts the Active Trip full-screen recording
//  flow, and pushes into Trip Detail once a drive is saved.
//

import SwiftData
import SwiftUI

struct AppRootView: View {
    @State private var appEnvironment = AppEnvironment()
    @State private var path = NavigationPath()
    @State private var selectedTab: AppTab = .dashboard
    @State private var isRecording = false
    @State private var showsSplash = true
    // Splash shows on every launch. Onboarding (the "Konumu Etkinleştir"
    // screen) only joins it when location permission isn't usable yet —
    // once granted, every later launch goes straight from Splash to Home.
    // Starts false; the splash-completion handler below decides whether to
    // flip it on before revealing anything underneath.
    @State private var showsOnboarding = false
    @State private var guidanceSegment: Segment?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                Group {
                    if showsOnboarding {
                        OnboardingView(locationManager: appEnvironment.locationManager) {
                            withAnimation(.easeOut(duration: 0.4)) {
                                showsOnboarding = false
                            }
                        }
                    } else {
                        Group {
                            switch selectedTab {
                            case .trips:
                                TripsListView(
                                    locationManager: appEnvironment.locationManager,
                                    onSelectTrip: { trip in path.append(trip.id) }
                                )
                            case .dashboard:
                                DashboardView(
                                    locationManager: appEnvironment.locationManager,
                                    isRecording: $isRecording,
                                    guidanceSegment: guidanceSegment,
                                    onTripEnded: handleTripEnded
                                )
                            case .garage:
                                GarageView()
                            case .community:
                                CommunityView(onFollowSegment: followSegment)
                            case .routes:
                                RoutesTabView(onFollowSegment: followSegment)
                            }
                        }
                        // safeAreaInset (not a raw overlay) so the bar's
                        // footprint actually insets scrollable content —
                        // list rows and their tap targets never end up
                        // underneath it, unlike a ZStack overlay which only
                        // adjusts what's visible, not what's touchable.
                        .safeAreaInset(edge: .bottom) {
                            if !isRecording {
                                MainTabBar(selectedTab: $selectedTab)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 8)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isRecording)
                    }
                }
                // Pushes a Trip's Codable `id`, not the Trip (a SwiftData
                // model, not Codable) itself — NavigationPath needs to
                // serialize its elements for state restoration across
                // backgrounding, and a non-Codable element there silently
                // breaks the destination lookup until the next cold launch.
                .navigationDestination(for: UUID.self) { tripID in
                    if let trip = fetchTrip(id: tripID) {
                        TripDetailView(trip: trip)
                    }
                }
                // Segment/route detail pushes go through this single shared
                // stack too, not a NavigationStack owned by RoutesTabView or
                // GlobalLeaderboardListView — a nested stack's pushed screen
                // isn't reliably torn down just by this view's own
                // `selectedTab` switch changing away from it, which was
                // exactly why "Bu Rotayı Sür" could arm the route in the
                // background without the screen ever moving to Dashboard.
                .navigationDestination(for: Segment.self) { segment in
                    SegmentDetailView(segment: segment, onFollowSegment: followSegment)
                }
                .navigationDestination(for: String.self) { segmentId in
                    SegmentDetailLoaderView(segmentId: segmentId, onFollowSegment: followSegment)
                }
            }
            .environment(appEnvironment)
            .preferredColorScheme(.dark)
            // `path` is shared across every tab — without this, switching
            // tabs never popped whatever Trip/Segment detail was pushed on
            // top of the *previous* tab's root, so it silently kept
            // reappearing (and stacking up, one per trip ever opened that
            // session) the next time the stack's back button was used from
            // some other, unrelated context.
            .onChange(of: selectedTab) { _, _ in
                path = NavigationPath()
            }
            #if DEBUG
            .task {
                // Test-only hook: launching with -uiTestAutoStartTrip skips
                // straight past onboarding and starts a drive immediately,
                // so the full record → save → detail flow can be driven
                // without taps.
                guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoStartTrip") else { return }
                showsSplash = false
                showsOnboarding = false
                try? await Task.sleep(for: .seconds(1))
                isRecording = true
            }
            .task {
                // Test-only hook: launching with -uiTestAutoGarage switches
                // straight to the Garage tab so it can be verified without taps.
                guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoGarage") else { return }
                try? await Task.sleep(for: .seconds(1))
                selectedTab = .garage
            }
            .task {
                // Test-only hook: launching with -uiTestAutoCommunity switches
                // straight to the Liderlik tab so it can be verified without taps.
                guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoCommunity") else { return }
                try? await Task.sleep(for: .seconds(1))
                selectedTab = .community
            }
            .task {
                // Test-only hook: launching with -uiTestAutoRoutes switches
                // straight to the Rotalar tab so it can be verified without taps.
                guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoRoutes") else { return }
                try? await Task.sleep(for: .seconds(1))
                selectedTab = .routes
            }
            .task {
                // Test-only hook: builds a Segment directly from the most
                // recently saved trip's own samples — bypassing CloudKit,
                // which is still behind FeatureFlags — arms it as Route
                // Following's target, and starts recording immediately.
                // Lets a second live-simulated drive of the same route be
                // verified against real turn instructions/ghost overlay
                // without needing the CloudKit capability active.
                guard ProcessInfo.processInfo.arguments.contains("-uiTestGuidanceFromLastTrip") else { return }
                showsSplash = false
                showsOnboarding = false
                try? await Task.sleep(for: .seconds(1))
                var descriptor = FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
                descriptor.fetchLimit = 1
                guard let trip = try? modelContext.fetch(descriptor).first else { return }
                let samples = trip.samples
                guard let segment = Segment.fromTripRange(
                    samples: samples, startIndex: 0, endIndex: samples.count - 1,
                    name: "Test Rota", creatorId: "me", creatorNickname: "Sen"
                ) else { return }
                selectedTab = .garage
                guidanceSegment = segment
                try? await Task.sleep(for: .milliseconds(500))
                selectedTab = .dashboard
                try? await Task.sleep(for: .milliseconds(500))
                isRecording = true
            }
            .task {
                // Test-only hook: launching with -uiTestAutoOpenTrip switches to
                // the Sürüşlerim tab and pushes the most recent trip, so the
                // list-row-tap → Trip Detail path can be verified without taps.
                guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoOpenTrip") else { return }
                try? await Task.sleep(for: .seconds(1))
                selectedTab = .trips
                try? await Task.sleep(for: .seconds(1))
                var descriptor = FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
                descriptor.fetchLimit = 1
                if let trip = try? modelContext.fetch(descriptor).first {
                    path.append(trip.id)
                }
            }
            #endif

            if showsSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .task {
            // Skips the splash wait entirely during automated test runs so
            // the debug hooks above aren't slowed down by it.
            let isUITest = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-uiTest") }
            try? await Task.sleep(for: .seconds(isUITest ? 0.2 : 3.5))
            // Decided once, right as the splash finishes: permission not
            // usable yet → reveal Onboarding underneath (it then stays on
            // screen until the user actually grants/denies, no timer).
            // Already usable → reveal Home directly, Onboarding never shows.
            if !appEnvironment.locationManager.hasUsableAuthorization {
                showsOnboarding = true
            }
            withAnimation(.easeOut(duration: 0.4)) {
                showsSplash = false
            }
        }
    }

    /// Dashboard hands back a finished recording (already past the "too
    /// short to save" check) the moment the user taps Sürüşü Bitir — no
    /// modal dismissal to wait for anymore, so this runs immediately.
    private func handleTripEnded(_ result: ActiveTripViewModel.TripResult) {
        let trip = Trip(samples: result.samples, stopEvents: result.stopEvents, stats: result.stats, score: result.score)
        modelContext.insert(trip)
        path.append(trip.id)
        resolvePlaceNames(for: trip)
        Task { await SegmentAutoMatcher.run(for: trip) }
        // A followed route only applies to the one drive it was armed for.
        guidanceSegment = nil
    }

    /// "Bu Rotayı Sür" in a Segment's detail screen — arms Dashboard with
    /// this route (ghost overlay + turn hints), switches to it, and starts
    /// recording immediately: unlike the tab bar's own Ana Sayfa button,
    /// tapping "follow this route" *is* the explicit "start driving" action.
    /// The short delay before flipping isRecording matters — Dashboard's
    /// ActiveTripViewModel only reads guidanceSegment when it's first
    /// constructed (right as .dashboard becomes selectedTab), and its
    /// .onChange(of: isRecording) only fires on an actual change, not the
    /// initial value, so isRecording has to go true *after* Dashboard has
    /// already mounted with isRecording still false.
    private func followSegment(_ segment: Segment) {
        guidanceSegment = segment
        selectedTab = .dashboard
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            isRecording = true
        }
    }

    private func fetchTrip(id: UUID) -> Trip? {
        var descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Fire-and-forget: fills in the trip row's "City → City" label once
    /// reverse geocoding resolves. Fine to fail silently (offline, rate
    /// limited) — Home falls back to the date in that case.
    private func resolvePlaceNames(for trip: Trip) {
        guard let start = trip.samples.first, let end = trip.samples.last else { return }
        Task {
            async let startName = PlaceNameResolver.resolve(coordinate: start.coordinate)
            async let endName = PlaceNameResolver.resolve(coordinate: end.coordinate)
            trip.startPlaceName = await startName
            trip.endPlaceName = await endName
            try? modelContext.save()
        }
    }
}
