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

import CoreLocation
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
    @State private var prefersDarkMap = false
    // Our own stand-in for what MapCameraPosition.userLocation(fallback:)
    // used to give us for free (continuous follow until the user pans
    // away) — dropped along with it to stop MapKit's own blue dot from
    // appearing as a side effect of that specific API (see
    // recenterOnKnownLocation's comment). true = keep recentering on every
    // new GPS sample while idle; flips false the moment onRegionChange
    // sees the camera move somewhere we didn't put it ourselves.
    @State private var isFollowingLocation = true
    @State private var lastAutoCenteredCoordinate: CLLocationCoordinate2D?
    @State private var resumeFollowingTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var systemColorScheme
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

            if showsSatelliteChase {
                // While idle there's no trip in progress to draw a route
                // from — feed just the current position (when known) so
                // the camera centers there and the dot shows, same as the
                // 2D idle map's own idlePositionCoordinate.
                LiveSatelliteMapView(
                    samples: isRecording ? tripViewModel.samples : [locationManager.latestSample].compactMap { $0 },
                    crewMarkers: isRecording ? crewMarkers : [],
                    ghostRouteCoordinates: ghostRouteCoordinates
                )
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
                        // A region change we didn't cause ourselves (see
                        // recenterOnKnownLocation) means the user dragged
                        // the map — stop auto-following until they're back
                        // idle again, same as Apple Maps losing tracking
                        // mode the moment you pan away from it.
                        if let lastAutoCenteredCoordinate {
                            let moved = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
                                .distance(from: CLLocation(latitude: lastAutoCenteredCoordinate.latitude, longitude: lastAutoCenteredCoordinate.longitude))
                            if moved > 30 {
                                isFollowingLocation = false
                                // Resume auto-following on its own after a
                                // few seconds of no further interaction —
                                // browsing the map for a bit shouldn't
                                // require ending/restarting a drive (or
                                // leaving and reopening Ana Sayfa) just to
                                // get back to "where am I". Each new pan
                                // restarts this countdown (old one
                                // cancelled below) so active browsing is
                                // never interrupted mid-gesture.
                                resumeFollowingTask?.cancel()
                                resumeFollowingTask = Task {
                                    try? await Task.sleep(for: .seconds(3.5))
                                    guard !Task.isCancelled, !isRecording else { return }
                                    isFollowingLocation = true
                                    withAnimation { recenterOnKnownLocation() }
                                }
                            }
                        }
                        Task { await loadDiscoverySegments(around: region) }
                    },
                    mapOpacity: isRecording ? 0.4 : 1.0,
                    // Kept warm by startIdleMapTracking (own LocationManager,
                    // same single source recording uses) — drawn as native
                    // Annotation content, not our screen-space Canvas, so it
                    // tracks a drag perfectly instead of lagging behind it
                    // (confirmed live).
                    idlePositionCoordinate: isRecording ? nil : locationManager.latestSample?.coordinate,
                    // North-up 2D map, not a heading-rotated one — rotating
                    // the car icon by compass heading here made it look
                    // wrong/tilted even driving dead straight (confirmed
                    // live: GPS heading noise at speed, or just not what
                    // "up" means on a map that doesn't itself rotate).
                    // Always pointing up reads correctly regardless.
                    idleHeadingDegrees: nil,
                    prefersDarkMapStyle: prefersDarkMap
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

            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        // 3D chase view — usable before a drive starts too
                        // now, not just during one (previously locked
                        // behind isRecording; confirmed the user wants to
                        // preview/use it from Ana Sayfa as well).
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { showsSatelliteChase.toggle() }
                        } label: {
                            Image(systemName: showsSatelliteChase ? "map.fill" : "globe.americas.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColor.accent)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(.ultraThinMaterial))
                        }

                        // The 2D map's road style is forced light regardless
                        // of system appearance (legible against this app's
                        // dark UI) — only worth offering a dark-map opt-out
                        // when the system is actually in dark mode, and only
                        // meaningful for the 2D map (satellite imagery has
                        // no light/dark variant).
                        if systemColorScheme == .dark, !showsSatelliteChase {
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) { prefersDarkMap.toggle() }
                            } label: {
                                Image(systemName: prefersDarkMap ? "moon.fill" : "moon")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColor.accent)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(.ultraThinMaterial))
                            }
                        }
                    }
                    .padding(.trailing, 20)
                }
                Spacer()
            }
            .padding(.top, 60)
        }
        .onAppear {
            if !isRecording {
                recenterOnKnownLocation()
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
                // live, reported as "no location"). Forces it back to
                // the real position before the first sample's own
                // heading-up tracking (below) takes over.
                withAnimation { recenterOnKnownLocation() }
                discoveredSegmentsById = [:]
                selectedSegmentId = nil
                previewSegment = nil
            } else {
                showsSatelliteChase = false
                crewMarkers = []
                locationManager.startIdleMapTracking()
                // Back to idle after a drive — resume auto-following, same
                // as a fresh app launch would.
                isFollowingLocation = true
                recenterOnKnownLocation()
            }
        }
        .onChange(of: locationManager.latestSample?.id) { _, _ in
            guard !isRecording, isFollowingLocation else { return }
            recenterOnKnownLocation()
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
    /// Was `cameraPosition = .userLocation(fallback: .automatic)` — that
    /// specific MapKit API turns on MapKit's own blue "puck" as a side
    /// effect of binding the camera to it, even with no `UserAnnotation()`
    /// anywhere in the app (confirmed live: a blue dot appeared right next
    /// to our own green one on first launch, then vanished once the camera
    /// moved away from `.userLocation` after a recording). Building the
    /// region from our own already-tracked coordinate instead centers the
    /// camera the same way without ever touching MapKit's tracking (which
    /// runs its own independent CLLocationManager and was already found,
    /// earlier this session, to measurably slow down our own GPS fix —
    /// that's why UserAnnotation was removed in the first place).
    private func recenterOnKnownLocation() {
        guard let sample = locationManager.latestSample else {
            cameraPosition = .automatic
            return
        }
        // Heading-up here too, not just while recording — the 3D idle map
        // (LiveSatelliteMapView, which always uses its own latest.heading
        // regardless of recording state) already rotated to match travel
        // direction while idle; this hardcoded 0 (always north-up) was
        // the one place still not matching it (confirmed live: two idle
        // screenshots side by side, 3D following the road's real direction
        // while 2D stayed north-fixed).
        cameraPosition = .camera(MapCamera(centerCoordinate: sample.coordinate, distance: 600, heading: sample.heading ?? 0, pitch: 0))
        lastAutoCenteredCoordinate = sample.coordinate
    }

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

        // Unbounded otherwise — a long session panning around a wide area
        // would just keep accumulating pins in memory forever. Once past
        // the cap, drop whichever are currently farthest from where the
        // user is actually looking; they're the ones least likely to
        // still be relevant, and panning back toward them re-discovers
        // them from CloudKit anyway.
        let cap = 400
        if discoveredSegmentsById.count > cap {
            let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
            let keep = discoveredSegmentsById.values.sorted { a, b in
                let aCenter = CLLocation(latitude: (a.minLatitude + a.maxLatitude) / 2, longitude: (a.minLongitude + a.maxLongitude) / 2)
                let bCenter = CLLocation(latitude: (b.minLatitude + b.maxLatitude) / 2, longitude: (b.minLongitude + b.maxLongitude) / 2)
                return center.distance(from: aCenter) < center.distance(from: bCenter)
            }.prefix(cap)
            discoveredSegmentsById = Dictionary(uniqueKeysWithValues: keep.map { ($0.id, $0) })
        }
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
