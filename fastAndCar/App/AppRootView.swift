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
    /// Set alongside guidanceSegment only when it was armed via a crew
    /// route (followCrewSegment) — tells handleTripEnded to also submit
    /// the finished drive as an effort into that crew's own zone, not just
    /// run the public Global Leaderboard auto-matcher.
    @State private var guidanceCrewZoneRef: CrewZoneRef?
    @State private var guidanceCrewId: String?
    @AppStorage("sharesLiveLocationWithCrew") private var sharesLiveLocationWithCrew = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

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
                                // .id() forces a fresh DashboardView (and its
                                // internal ActiveTripViewModel) whenever a
                                // *different* route gets armed — without it,
                                // switching back to an already-materialized
                                // Dashboard reused the previous
                                // ActiveTripViewModel, silently keeping its
                                // stale (or absent) guidanceTracker instead
                                // of picking up the route "Bu Rotayı Sür"
                                // just armed.
                                DashboardView(
                                    locationManager: appEnvironment.locationManager,
                                    isRecording: $isRecording,
                                    guidanceSegment: guidanceSegment,
                                    onTripEnded: handleTripEnded,
                                    onCancelRoute: {
                                        guidanceSegment = nil
                                        guidanceCrewZoneRef = nil
                                        guidanceCrewId = nil
                                    },
                                    onFollowSegment: followSegment
                                )
                                .id(guidanceSegment?.id)
                            case .garage:
                                GarageView()
                            case .community:
                                CommunityView(onFollowSegment: followSegment, onFollowCrewSegment: followCrewSegment)
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
                // Same shared-stack fix, applied to Crew's screens — they
                // used to live in their own NavigationStack nested inside
                // CommunityView, which is exactly the pattern that broke
                // "Bu Rotayı Sür" not visually switching to Dashboard.
                .navigationDestination(for: MyCrewRef.self) { ref in
                    CrewDetailView(crewRef: ref, onFollowCrewSegment: followCrewSegment)
                }
                .navigationDestination(for: CrewSegmentPush.self) { push in
                    CrewSegmentDetailView(segment: push.segment, crewId: push.crewId, zoneRef: push.zoneRef, onFollowSegment: followCrewSegment)
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
            // Ask for notification permission here, at launch, rather than
            // waiting until the first drive actually finishes and needs to
            // post one (SegmentAutoMatcher used to be the only caller) —
            // requestAuthorization's system prompt is async and doesn't
            // block, so a notification that needs to go out moments after
            // the very first prompt appears was racing the user's answer
            // and silently getting dropped if they hadn't responded yet.
            // Asking on launch gives that prompt plenty of time to resolve
            // before it's ever actually needed.
            LocalNotifier.requestAuthorizationIfNeeded()
        }
        .task {
            // "arkada açık olsa bile" — presence sharing now keeps running
            // in the background too, not just foreground: Always
            // authorization is requested the moment the toggle goes on
            // (below), and LocationManager only actually enables background
            // delivery once that's granted (falls back to foreground-only
            // like recording always has if the user only grants When-In-Use).
            if sharesLiveLocationWithCrew {
                appEnvironment.presenceBroadcaster.start()
            }
        }
        .onChange(of: sharesLiveLocationWithCrew) { _, isOn in
            if isOn {
                appEnvironment.locationManager.requestAlwaysAuthorizationIfNeeded()
                appEnvironment.presenceBroadcaster.start()
            } else {
                appEnvironment.presenceBroadcaster.stop()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back to foreground after Always wasn't granted yet (or
            // was just approved) — re-arm so the broadcaster picks up
            // wherever LocationManager's authorization now stands, instead
            // of staying stuck on whatever it saw at launch.
            guard sharesLiveLocationWithCrew, phase == .active else { return }
            appEnvironment.presenceBroadcaster.start()
        }
        #if DEBUG
        .task {
            // Test-only: jumps straight to a synthetic Segment's detail
            // screen (SegmentDetailView's own -uiTestSeedFakeLeaderboard
            // hook fills the ranked list) so the leaderboard's visual
            // design can be checked without needing several real CloudKit
            // accounts to race each other first.
            guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoOpenFakeLeaderboard") else { return }
            try? await Task.sleep(for: .milliseconds(300))
            let fakeSegment = Segment(
                id: "fake-segment",
                name: "Test Parkuru",
                creatorId: "fake-creator",
                creatorNickname: "turbo",
                polyline: [
                    RoutePolylinePoint(lat: 41.02, lon: 28.97),
                    RoutePolylinePoint(lat: 41.03, lon: 28.98),
                ],
                minLatitude: 41.02, minLongitude: 28.97,
                maxLatitude: 41.03, maxLongitude: 28.98,
                toleranceMeters: 25, bearingDegrees: 45,
                geohashes: [], createdAt: Date(),
                creatorDurationSeconds: 60, voteCount: 3
            )
            path.append(fakeSegment)
        }
        #endif
        .task {
            // Best-effort, once per launch. Two cases:
            // - Local nickname already set: publish it (covers anyone who
            //   picked a nickname before the by-name crew invite feature
            //   existed and so never had their handle synced to CloudKit).
            // - No local nickname (first launch, or a delete-and-reinstall
            //   that wiped UserDefaults): try to recover an existing handle
            //   from CloudKit first, keyed by the CloudKit userId which
            //   survives reinstalls — so a friend's saved "nickname#tag"
            //   for this person, and this person's own identity, don't
            //   silently break just because the app was reinstalled.
            let store = NicknameStore()
            if store.hasNickname {
                try? await CloudKitProfileService.syncHandle(nickname: store.nickname, tag: store.tag)
            } else if let recovered = try? await CloudKitProfileService.fetchMyHandle() {
                store.restore(nickname: recovered.nickname, tag: recovered.tag)
            }
        }
        .task {
            // First launch (permission not decided yet) used to always sit
            // through the full splash animation *then* have Onboarding's
            // own animated intro play right after it — the same kind of
            // "effect" twice in a row. Checked upfront now: if Onboarding
            // is going to show anyway, skip the splash wait/animation
            // entirely and go straight there: only one intro, not two.
            guard appEnvironment.locationManager.hasUsableAuthorization else {
                showsSplash = false
                showsOnboarding = true
                return
            }
            // Returning user, permission already usable — splash plays
            // normally, then straight to Home, Onboarding never shows.
            let isUITest = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-uiTest") }
            try? await Task.sleep(for: .seconds(isUITest ? 0.2 : 3.5))
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
        // This drive was explicitly following one specific crew route (not
        // a general "was I near any public segment" auto-detect) — already
        // know exactly which segment and zone, so submit straight to it
        // rather than searching.
        if let crewZoneRef = guidanceCrewZoneRef, let crewId = guidanceCrewId, let followedSegment = guidanceSegment {
            let samples = trip.samples
            let score = trip.drivingScoreValue
            Task {
                guard let match = SegmentMatcher.match(trip: samples, against: followedSegment) else { return }
                let nickname = NicknameStore().nickname
                guard let userId = try? await CloudKitCrewService.currentUserId() else { return }
                try? await CloudKitCrewService.submitEffort(
                    segmentId: followedSegment.id,
                    crewId: crewId,
                    userId: userId,
                    nickname: nickname,
                    match: match,
                    drivingScore: score,
                    zoneRef: crewZoneRef
                )
            }
        }
        checkForNewlyUnlockedAchievements()
        syncProfileStatsToCloud()
        // A followed route only applies to the one drive it was armed for.
        guidanceSegment = nil
        guidanceCrewZoneRef = nil
        guidanceCrewId = nil
    }

    /// Publishes this device's totals + garage onto the public UserProfile
    /// record so other users can see a real profile (not just photo/name)
    /// when they tap this person's name on a leaderboard — best-effort,
    /// mirrors every other sync call in this codebase (try?, no UI feedback).
    private func syncProfileStatsToCloud() {
        guard let trips = try? modelContext.fetch(FetchDescriptor<Trip>()),
              let cars = try? modelContext.fetch(FetchDescriptor<Car>()) else { return }
        let totalDistanceMeters = trips.reduce(0) { $0 + $1.distanceMeters }
        let totalDriveTime = trips.reduce(0) { $0 + $1.driveTime }
        let carEntries = cars.map { CloudKitProfileService.CarSyncEntry(name: "\($0.year) \($0.displayName)", photoData: $0.photoData) }
        Task {
            try? await CloudKitProfileService.syncStats(
                totalDistanceMeters: totalDistanceMeters,
                tripCount: trips.count,
                totalDriveTime: totalDriveTime,
                cars: carEntries
            )
        }
    }

    /// Re-evaluates the full badge set against every trip on disk (cheap —
    /// AchievementEvaluator only reads denormalized Trip fields, no sample
    /// decoding) and notifies for whatever wasn't already notified before.
    private func checkForNewlyUnlockedAchievements() {
        guard let allTrips = try? modelContext.fetch(FetchDescriptor<Trip>()) else { return }
        let unlocked = AchievementEvaluator.unlockedIds(for: allTrips)
        var store = NotifiedAchievementsStore()
        let newIds = store.newlyUnlocked(from: unlocked)
        for id in newIds {
            guard let achievement = AchievementCatalog.all.first(where: { $0.id == id }) else { continue }
            LocalNotifier.notifyAchievementUnlocked(title: achievement.title)
        }
    }

    /// "Bu Rotayı Sür" in a Segment's detail screen — arms Dashboard with
    /// this route (ghost overlay + turn hints) and switches to it, but does
    /// NOT start recording automatically: the driver lands on Ana Sayfa in
    /// the "Rota Hazır" state and has to explicitly tap Sürüşe Başla (or
    /// Rotayı İptal Et to back out) — armed and driving are two separate,
    /// user-confirmed steps.
    private func followSegment(_ segment: Segment) {
        // Cleared here rather than left to the .onChange(of: selectedTab)
        // side effect below — popping the pushed Segment detail screen and
        // switching the visible tab in the same synchronous step avoids a
        // brief window where the tab has changed but the stack is still
        // showing the old push on top of it.
        path = NavigationPath()
        guidanceSegment = segment
        guidanceCrewZoneRef = nil
        selectedTab = .dashboard
    }

    /// Same as followSegment, just also remembers which crew zone to
    /// submit the finished drive's effort into (see handleTripEnded).
    private func followCrewSegment(_ segment: Segment, crewId: String, zoneRef: CrewZoneRef) {
        path = NavigationPath()
        guidanceSegment = segment
        guidanceCrewZoneRef = zoneRef
        guidanceCrewId = crewId
        selectedTab = .dashboard
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
