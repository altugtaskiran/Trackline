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
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault }
    // Live-drive-only: a 3D satellite chase view following the current GPS
    // fix, offered as an alternative to the flat live route map while
    // actually recording. Not available for reviewing a finished trip — see
    // LiveSatelliteMapView's header comment for why that placement got
    // pulled.
    @State private var showsSatelliteChase = false
    // Crew members' live locations, overlaid on this same driving map — "if
    // a crewmate is nearby or headed the same way, see them while I drive",
    // not just on the separate Crew screen. Only polled while actually
    // recording, to avoid an idle-screen background task.
    @State private var crewMarkers: [CrewMapMarker] = []
    @State private var myUserId: String?
    // Route discovery — only active while idle (not recording): nearby
    // popular routes drawn as tappable colored lines, refetched as the
    // user pans the map. A minimum vote count keeps unrated/spam routes
    // off the map entirely (they still exist in Global Rotalar, just not
    // rendered here) — see CloudKitSegmentService.fetchNearbySegments.
    // Keyed by id and merged into (never wholesale-replaced) by
    // loadDiscoverySegments below — a pin that's already been shown stays
    // on the map even if a later, slightly-panned viewport query doesn't
    // happen to re-surface it. Previously every camera move replaced the
    // whole array with just that query's results, so a pin near the edge
    // of the padded search window could flicker away on a tiny pan and
    // only reappear once a later query's cells happened to include it
    // again — confirmed live: near-identical zoom levels, same pin
    // visible in one screenshot and gone in the next.
    @State private var discoveredSegmentsById: [String: Segment] = [:]
    private var discoverySegments: [Segment] { Array(discoveredSegmentsById.values) }
    @State private var selectedSegmentId: String?
    @State private var previewSegment: Segment?
    private let discoveryMinVoteCount = 3
    private let discoveryLimit = 60
    @Binding var isRecording: Bool
    let locationManager: LocationManager
    var onTripEnded: (ActiveTripViewModel.TripResult) -> Void
    var onCancelRoute: () -> Void
    var onFollowSegment: (Segment) -> Void

    init(
        locationManager: LocationManager,
        isRecording: Binding<Bool>,
        guidanceSegment: Segment? = nil,
        onTripEnded: @escaping (ActiveTripViewModel.TripResult) -> Void,
        onCancelRoute: @escaping () -> Void = {},
        onFollowSegment: @escaping (Segment) -> Void = { _ in }
    ) {
        self.locationManager = locationManager
        _viewModel = State(initialValue: HomeViewModel(locationManager: locationManager))
        _tripViewModel = State(initialValue: ActiveTripViewModel(locationManager: locationManager, guidanceSegment: guidanceSegment))
        _isRecording = isRecording
        self.onTripEnded = onTripEnded
        self.onCancelRoute = onCancelRoute
        self.onFollowSegment = onFollowSegment
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

            if isRecording && showsSatelliteChase {
                LiveSatelliteMapView(samples: tripViewModel.samples, crewMarkers: crewMarkers, ghostRouteCoordinates: ghostRouteCoordinates)
                    .ignoresSafeArea()
            } else {
                LiveRouteMapView(
                    samples: isRecording ? tripViewModel.samples : [],
                    cameraPosition: $cameraPosition,
                    ghostRouteCoordinates: ghostRouteCoordinates,
                    crewMarkers: isRecording ? crewMarkers : [],
                    interactionModes: isRecording ? [] : [.pan, .zoom],
                    discoverySegments: isRecording ? [] : discoverySegments,
                    selectedSegmentId: selectedSegmentId,
                    onSelectSegment: { id in
                        selectedSegmentId = id
                        previewSegment = id.flatMap { selectedId in discoverySegments.first { $0.id == selectedId } }
                    },
                    onRegionChange: { region in
                        guard !isRecording else { return }
                        Task { await loadDiscoverySegments(around: region) }
                    },
                    mapOpacity: isRecording ? 0.22 : 1.0,
                    // Kept warm by startIdleMapTracking (own LocationManager,
                    // same single source recording uses) — drawn as native
                    // Annotation content, not our screen-space Canvas, so it
                    // tracks a drag perfectly instead of lagging behind it
                    // (confirmed live).
                    idlePositionCoordinate: isRecording ? nil : locationManager.latestSample?.coordinate
                )
                .ignoresSafeArea()

                // Lighter than before — the flat map underneath is already
                // faint (LiveRouteMapView renders it at 0.22 opacity), so
                // the old scrim was stacking on top of that and reading as
                // just plain dark. Satellite mode (above) stays scrim-free
                // entirely — its imagery has enough contrast on its own for
                // the overlaid text/buttons.
                LinearGradient(
                    colors: [
                        AppColor.background.opacity(0.25),
                        AppColor.background.opacity(0.05),
                        AppColor.background.opacity(0.35),
                        AppColor.background.opacity(0.55),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

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
                        Text("\(distanceUnit.speedValue(kph: tripViewModel.currentSpeedKph))")
                            .font(AppFont.hero())
                            .foregroundStyle(AppColor.textPrimary)
                            .numeralTracking()
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: tripViewModel.currentSpeedKph)
                        Text(distanceUnit.speedSymbol)
                            .font(AppFont.statLabel)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    HStack(spacing: 40) {
                        LiveStatBadge(title: "Süre", value: formattedElapsed)
                        LiveStatBadge(title: "Mesafe", value: distanceUnit.distanceString(meters: tripViewModel.distanceMeters))
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
                .padding(.bottom, (!isRecording && tripViewModel.guidanceTracker?.segment != nil) ? 12 : (isRecording ? 40 : 100))

                if !isRecording, tripViewModel.guidanceTracker?.segment != nil {
                    Button {
                        onCancelRoute()
                    } label: {
                        Label("Rotayı İptal Et", systemImage: "xmark")
                    }
                    .buttonStyle(.glass(.destructive))
                    .padding(.bottom, 100)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isRecording)

            if isRecording {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { showsSatelliteChase.toggle() }
                        } label: {
                            Image(systemName: showsSatelliteChase ? "map.fill" : "globe.americas.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColor.accent)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(.ultraThinMaterial))
                        }
                        .padding(.trailing, 20)
                    }
                    Spacer()
                }
                .padding(.top, 60)
            }
        }
        .onAppear {
            if !isRecording {
                cameraPosition = .userLocation(fallback: .automatic)
                locationManager.startIdleMapTracking()
            }
        }
        .onDisappear {
            locationManager.stopIdleMapTracking()
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                locationManager.stopIdleMapTracking()
                tripViewModel.start()
                // .automatic alone doesn't recenter on the user — it just
                // keeps whatever region is already showing. That was
                // harmless before (idle map was always locked on the
                // user), but now that idle browsing lets you drag the map
                // anywhere, starting a drive left the camera stuck wherever
                // it'd been dragged to — the live route/position dot were
                // still drawing correctly, just off-screen (confirmed
                // live, reported as "no location"). .userLocation forces
                // it back to the real position before the first sample's
                // own heading-up tracking (below) takes over.
                withAnimation { cameraPosition = .userLocation(fallback: .automatic) }
                discoveredSegmentsById = [:]
                selectedSegmentId = nil
                previewSegment = nil
            } else {
                showsSatelliteChase = false
                crewMarkers = []
                locationManager.startIdleMapTracking()
            }
        }
        .sheet(item: $previewSegment, onDismiss: { selectedSegmentId = nil }) { segment in
            RoutePreviewSheet(
                segment: segment,
                onFollow: { followed in
                    previewSegment = nil
                    selectedSegmentId = nil
                    onFollowSegment(followed)
                },
                onDismiss: { previewSegment = nil }
            )
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .task(id: isRecording) {
            guard isRecording, FeatureFlags.crewEnabled else { return }
            if myUserId == nil {
                myUserId = try? await CloudKitCrewService.currentUserId()
            }
            // Membership rosters fetched once per drive (not every poll —
            // who's in a crew doesn't change mid-drive, only where they are).
            let crews = MyCrewsStore().crews
            var rosters: [(zoneRef: CrewZoneRef, memberIds: [String], nicknames: [String: String])] = []
            for crewRef in crews {
                guard let members = try? await CloudKitCrewService.fetchMembers(zoneRef: crewRef.zoneRef) else { continue }
                let ids = members.map(\.userId).filter { $0 != myUserId }
                guard !ids.isEmpty else { continue }
                // uniquingKeysWith, not uniqueKeysWithValues: a duplicate
                // CrewMembership row for the same userId (membership records
                // use a random UUID as their own ID, so this can happen) made
                // uniqueKeysWithValues trap with a fatal error — confirmed
                // live, this was crashing "Sürüşe Başla" outright.
                let nicknameByUserId = Dictionary(members.map { ($0.userId, $0.nickname) }, uniquingKeysWith: { first, _ in first })
                rosters.append((crewRef.zoneRef, ids, nicknameByUserId))
            }
            guard !rosters.isEmpty else { return }

            while !Task.isCancelled && isRecording {
                var merged: [String: CrewMapMarker] = [:]
                for roster in rosters {
                    guard let locations = try? await CloudKitCrewService.fetchLiveLocations(memberUserIds: roster.memberIds, zoneRef: roster.zoneRef) else { continue }
                    for location in locations where location.isActive {
                        merged[location.userId] = CrewMapMarker(
                            userId: location.userId,
                            nickname: roster.nicknames[location.userId] ?? "?",
                            coordinate: location.coordinate
                        )
                    }
                }
                crewMarkers = Array(merged.values)
                try? await Task.sleep(for: .seconds(8))
            }
        }
        .onChange(of: tripViewModel.samples.last?.id) { _, _ in
            // Heading-up, not north-up: the camera's `heading` tracks the
            // car's own course, so the road ahead is always toward the top
            // of the screen instead of the phone's physical top only
            // matching that when you happen to be driving north. Falls
            // back to true north (0°) only while course is still unknown
            // (e.g. the very first fix, before the device has moved enough
            // for CoreLocation to derive a heading from GPS).
            guard isRecording, let latest = tripViewModel.samples.last else { return }
            withAnimation(.easeOut(duration: 0.6)) {
                cameraPosition = .camera(
                    MapCamera(centerCoordinate: latest.coordinate, distance: 600, heading: latest.heading ?? 0, pitch: 0)
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

    /// Refetches nearby popular routes for the map's current viewport —
    /// called on first appear and after every pan/zoom (LiveRouteMapView's
    /// onRegionChange, itself only firing once per completed gesture).
    ///
    /// Two zoom-dependent quirks fixed here (both confirmed live):
    /// - Zoomed in tight, a route already partly on screen could still
    ///   disappear — the query region matched the viewport exactly, and a
    ///   route's own (downsampled, ~40-point) geohash tags don't cover
    ///   every point along it, so a tiny viewport could miss the one
    ///   tagged cell nearby. Padding the query region fixes it.
    /// - Zoomed out past ~60 precision-6 cells' worth of area, the query
    ///   just silently stopped updating (see the old comment below) —
    ///   routes already drawn stayed frozen in place while newly-panned-to
    ///   ones never loaded. Now it switches to the same coarse
    ///   (precision-4) cells "Yakınımdakiler" uses once the viewport gets
    ///   that wide, so the search never actually stops, just gets coarser.
    private func loadDiscoverySegments(around region: MKCoordinateRegion) async {
        guard FeatureFlags.globalLeaderboardEnabled else { return }
        // 3x (not just enough to cover the visible viewport) on purpose —
        // now that results are merged in rather than replacing what's
        // already shown (see discoveredSegmentsById), a wider scan per
        // load means panning around inside that already-scanned margin
        // needs no new query at all, instead of refetching on every
        // single pan.
        let padded = MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(latitudeDelta: region.span.latitudeDelta * 3, longitudeDelta: region.span.longitudeDelta * 3)
        )
        var fetched: [Segment]?
        if let cells = Geohash.cells(covering: padded) {
            fetched = try? await CloudKitSegmentService.fetchNearbySegments(
                candidateGeohashes: cells,
                minVoteCount: discoveryMinVoteCount,
                limit: discoveryLimit
            )
        } else if let coarseCells = Geohash.cells(covering: padded, precision: Geohash.coarsePrecision) {
            fetched = try? await CloudKitSegmentService.fetchNearbySegmentsWide(
                candidateCoarseGeohashes: coarseCells,
                minVoteCount: discoveryMinVoteCount,
                limit: discoveryLimit
            )
        }
        // Merge in, don't replace — a pin already on the map stays put;
        // panning only ever discovers more of them, never drops one that
        // was already found (see discoveredSegmentsById's doc comment).
        for segment in fetched ?? [] {
            discoveredSegmentsById[segment.id] = segment
        }
        // Else: zoomed out past even the coarse grid's 60-cell cap (a
        // whole-country-scale view) — leave whatever's already drawn.
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
