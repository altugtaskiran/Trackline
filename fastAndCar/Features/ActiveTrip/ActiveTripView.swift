//
//  ActiveTripView.swift
//  fastAndCar
//
//  Full-black live recording screen: a big speed numeral, a growing route
//  line, and exactly one unavoidable action — End Drive.
//

import MapKit
import SwiftUI

struct ActiveTripView: View {
    @State private var viewModel: ActiveTripViewModel
    @State private var cameraPosition: MapCameraPosition = .automatic
    var onEnd: (ActiveTripViewModel.TripResult?) -> Void

    init(locationManager: LocationManager, onEnd: @escaping (ActiveTripViewModel.TripResult?) -> Void) {
        _viewModel = State(initialValue: ActiveTripViewModel(locationManager: locationManager))
        self.onEnd = onEnd
    }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            LiveRouteMapView(samples: viewModel.samples, cameraPosition: $cameraPosition)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    AppColor.background.opacity(0.5),
                    AppColor.background.opacity(0.05),
                    AppColor.background.opacity(0.7),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                if viewModel.isStopped {
                    Text("Duraklatıldı")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().strokeBorder(AppColor.glassBorderSubtle, lineWidth: 1))
                        .padding(.top, 64)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Spacer()
            }

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 2) {
                    Text(String(format: "%.0f", viewModel.currentSpeedKph))
                        .font(AppFont.hero())
                        .foregroundStyle(AppColor.textPrimary)
                        .numeralTracking()
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.currentSpeedKph)
                    Text("km/h")
                        .font(AppFont.statLabel)
                        .foregroundStyle(AppColor.textSecondary)
                }

                HStack(spacing: 40) {
                    LiveStatBadge(title: "Süre", value: formattedElapsed)
                    LiveStatBadge(title: "Mesafe", value: String(format: "%.1f km", viewModel.distanceMeters / 1000))
                }
                .padding(.top, 28)

                Button("Sürüşü Bitir") {
                    onEnd(viewModel.end())
                }
                .buttonStyle(.glass(.destructive))
                .padding(.top, 36)
                .padding(.bottom, 56)
            }
        }
        .onAppear { viewModel.start() }
        .onChange(of: viewModel.samples.last?.id) { _, _ in
            guard let latest = viewModel.samples.last else { return }
            withAnimation(.easeOut(duration: 0.6)) {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: latest.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
                    )
                )
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isStopped)
        .toolbar(.hidden, for: .navigationBar)
        #if DEBUG
        .task {
            // Test-only hook: launching with -uiTestAutoEnd ends the drive
            // after a fixed delay (override with -uiTestAutoEndSeconds N) so
            // Trip Detail can be reached without taps.
            guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoEnd") else { return }
            let args = ProcessInfo.processInfo.arguments
            let seconds: Double
            if let flagIndex = args.firstIndex(of: "-uiTestAutoEndSeconds"),
               args.indices.contains(flagIndex + 1),
               let parsed = Double(args[flagIndex + 1]) {
                seconds = parsed
            } else {
                seconds = 17
            }
            try? await Task.sleep(for: .seconds(seconds))
            onEnd(viewModel.end())
        }
        #endif
    }

    private var formattedElapsed: String {
        let total = Int(viewModel.elapsedTime)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0 ? String(format: "%dh %02dm", hours, minutes) : String(format: "%dm %02ds", minutes, seconds)
    }
}
