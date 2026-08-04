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
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if appEnvironment.hasCompletedOnboarding {
                    HomeView(
                        locationManager: appEnvironment.locationManager,
                        onStartTrip: { activeTripPresented = true },
                        onSelectTrip: { trip in path.append(trip) }
                    )
                } else {
                    OnboardingView(locationManager: appEnvironment.locationManager) {
                        appEnvironment.hasCompletedOnboarding = true
                    }
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
            // onboarding and starts a drive immediately, so the full
            // record → save → detail flow can be driven without taps.
            guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoStartTrip") else { return }
            appEnvironment.hasCompletedOnboarding = true
            try? await Task.sleep(for: .seconds(1))
            activeTripPresented = true
        }
        #endif
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
