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
    @State private var activeTripPresented = false
    @State private var pendingTripResult: ActiveTripViewModel.TripResult?
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
                        HomeView(
                            locationManager: appEnvironment.locationManager,
                            onStartTrip: { activeTripPresented = true },
                            onSelectTrip: { trip in path.append(trip) }
                        )
                    }
                }
                .navigationDestination(for: Trip.self) { trip in
                    TripDetailView(trip: trip)
                }
            }
            .fullScreenCover(isPresented: $activeTripPresented, onDismiss: handleActiveTripDismissed) {
                ActiveTripView(locationManager: appEnvironment.locationManager) { result in
                    pendingTripResult = result
                    activeTripPresented = false
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
                activeTripPresented = true
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

    /// Runs after the Active Trip cover has fully dismissed — creating the
    /// Trip and pushing navigation here (rather than in the same tick as the
    /// dismissal) avoids a race where the NavigationStack drops a path
    /// mutation made while the cover is still animating away.
    private func handleActiveTripDismissed() {
        guard let result = pendingTripResult else { return }
        pendingTripResult = nil
        let trip = Trip(samples: result.samples, stopEvents: result.stopEvents, stats: result.stats, score: result.score)
        modelContext.insert(trip)
        path.append(trip)
        resolvePlaceNames(for: trip)
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
