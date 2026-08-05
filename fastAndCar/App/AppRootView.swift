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
                                    onTripEnded: handleTripEnded
                                )
                            case .garage:
                                GarageView()
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
            }
            .environment(appEnvironment)
            .preferredColorScheme(.dark)
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
