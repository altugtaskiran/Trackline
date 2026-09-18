//
//  DashboardView.swift
//  fastAndCar
//
//  The center tab — one persistent screen, not two. The same LiveRouteMapView
//  instance is on screen whether idle or recording (idle: just the user's
//  own position via UserAnnotation; recording: the growing route on top of
//  it); starting a drive never swaps in a different view or slides up a
//  modal — it just changes what this screen is showing, in place, and the
//  Start button turns into Sürüşü Bitir.
//

import MapKit
import SwiftUI

struct DashboardView: View {
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var viewModel: HomeViewModel
    @State private var tripViewModel: ActiveTripViewModel
    @State private var showsTooShortAlert = false
    @Binding var isRecording: Bool
    let locationManager: LocationManager
    var onTripEnded: (ActiveTripViewModel.TripResult) -> Void

    init(
        locationManager: LocationManager,
        isRecording: Binding<Bool>,
        guidanceSegment: Segment? = nil,
        onTripEnded: @escaping (ActiveTripViewModel.TripResult) -> Void
    ) {
        self.locationManager = locationManager
        _viewModel = State(initialValue: HomeViewModel(locationManager: locationManager))
        _tripViewModel = State(initialValue: ActiveTripViewModel(locationManager: locationManager, guidanceSegment: guidanceSegment))
        _isRecording = isRecording
        self.onTripEnded = onTripEnded
    }

    private var ghostRouteCoordinates: [CLLocationCoordinate2D] {
        // Shown as soon as a route is armed, not just once recording starts
        // — the point is confirming "yes, this is the route" before Sürüşe
        // Başla, not just during.
        guard let segment = tripViewModel.guidanceTracker?.segment else { return [] }
        return segment.polyline.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            LiveRouteMapView(
                samples: isRecording ? tripViewModel.samples : [],
                cameraPosition: $cameraPosition,
                ghostRouteCoordinates: ghostRouteCoordinates
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    AppColor.background.opacity(0.55),
                    AppColor.background.opacity(0.1),
                    AppColor.background.opacity(0.6),
                    AppColor.background.opacity(0.8),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                if isRecording {
                    if let instructionText = tripViewModel.guidanceTracker?.instructionText {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                .foregroundStyle(Color(hex: 0xBF5AF2))
                            Text(instructionText)
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().strokeBorder(AppColor.glassBorderSubtle, lineWidth: 1))
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: instructionText)
                    } else if tripViewModel.isStopped {
                        Text("Duraklatıldı")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.ultraThinMaterial))
                            .overlay(Capsule().strokeBorder(AppColor.glassBorderSubtle, lineWidth: 1))
                            .padding(.top, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                } else {
                    Text("Trackline")
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(.top, -4)
                        .transition(.opacity)
                }
                Spacer()
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: tripViewModel.isStopped)

            VStack(spacing: 14) {
                Spacer()

                if isRecording {
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f", tripViewModel.currentSpeedKph))
                            .font(AppFont.hero())
                            .foregroundStyle(AppColor.textPrimary)
                            .numeralTracking()
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: tripViewModel.currentSpeedKph)
                        Text("km/h")
                            .font(AppFont.statLabel)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    HStack(spacing: 40) {
                        LiveStatBadge(title: "Süre", value: formattedElapsed)
                        LiveStatBadge(title: "Mesafe", value: String(format: "%.1f km", tripViewModel.distanceMeters / 1000))
                        if let formattedSegmentElapsed {
                            LiveStatBadge(title: "Parkur", value: formattedSegmentElapsed)
                        }
                    }
                    .padding(.top, 28)
                } else if let segment = tripViewModel.guidanceTracker?.segment {
                    VStack(spacing: 2) {
                        Text("Rota Hazır")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(segment.name)
                            .font(AppFont.caption)
                            .foregroundStyle(Color(hex: 0xBF5AF2))
                    }
                } else {
                    Text("Sürüşe hazır")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                }

                Button {
                    if isRecording {
                        if let result = tripViewModel.end() {
                            isRecording = false
                            onTripEnded(result)
                        } else {
                            showsTooShortAlert = true
                        }
                    } else {
                        viewModel.startTripTapped(onAuthorized: { isRecording = true })
                    }
                } label: {
                    if isRecording {
                        Text("Sürüşü Bitir")
                    } else {
                        Label("Sürüşe Başla", systemImage: "location.fill")
                    }
                }
                .buttonStyle(.glass(isRecording ? .destructive : .accent))
                .padding(.bottom, isRecording ? 40 : 100)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isRecording)
        }
        .onAppear {
            if !isRecording { cameraPosition = .userLocation(fallback: .automatic) }
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                tripViewModel.start()
                withAnimation { cameraPosition = .automatic }
            }
        }
        .onChange(of: tripViewModel.samples.last?.id) { _, _ in
            guard isRecording, let latest = tripViewModel.samples.last else { return }
            withAnimation(.easeOut(duration: 0.6)) {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: latest.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
                    )
                )
            }
        }
        .alert("Sürüş Kaydedilemedi", isPresented: $showsTooShortAlert) {
            Button("Tamam") { isRecording = false }
        } message: {
            Text("Bu sürüş kaydedilemeyecek kadar kısa — en az birkaç saniye konum verisi gerekiyor.")
        }
        .alert("Konum İzni Gerekli", isPresented: $viewModel.showsPermissionAlert) {
            Button("Ayarları Aç") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Sürüşünü kaydedebilmek için Ayarlar'dan konum iznini etkinleştir.")
        }
        #if DEBUG
        .task {
            // Test-only hook: launching with -uiTestAutoEnd ends the drive
            // after a fixed delay (override with -uiTestAutoEndSeconds N).
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
            guard isRecording else { return }
            if let result = tripViewModel.end() {
                isRecording = false
                onTripEnded(result)
            } else {
                showsTooShortAlert = true
            }
        }
        #endif
    }

    private var formattedElapsed: String {
        let total = Int(tripViewModel.elapsedTime)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0 ? String(format: "%dh %02dm", hours, minutes) : String(format: "%dm %02ds", minutes, seconds)
    }

    // Nil until the driver's GPS actually reaches the segment's own start
    // point (see RouteGuidanceTracker.hasStarted) — the badge only appears
    // once the race clock has a real zero to count from, not from whenever
    // Sürüşe Başla happened to be tapped.
    private var formattedSegmentElapsed: String? {
        guard let elapsed = tripViewModel.guidanceTracker?.elapsedSeconds else { return nil }
        let total = max(0, Int(elapsed))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
