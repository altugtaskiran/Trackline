//
//  SegmentDetailView.swift
//  fastAndCar
//
//  Route preview (built from the segment's own stored polyline, not a live
//  trip) + the ranked SegmentEffort list, fastest time first.
//

import CoreLocation
import SwiftUI

struct SegmentDetailView: View {
    let segment: Segment
    var onFollowSegment: (Segment) -> Void

    @State private var entries: [SegmentEffort] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var voteCount: Int
    @State private var hasVoted = false
    @State private var isVoting = false
    @State private var myUserId: String?
    @State private var photoCache = ProfilePhotoCache.shared
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault }

    init(segment: Segment, onFollowSegment: @escaping (Segment) -> Void) {
        self.segment = segment
        self.onFollowSegment = onFollowSegment
        _voteCount = State(initialValue: segment.voteCount)
    }

    private var previewSamples: [LocationSample] {
        segment.polyline.enumerated().map { index, point in
            LocationSample(
                coordinate: CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon),
                timestamp: Date(timeIntervalSince1970: Double(index)),
                speedMps: 0,
                altitude: 0,
                heading: nil,
                horizontalAccuracy: 0
            )
        }
    }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    SegmentRouteMapPreview(coordinates: previewSamples.map(\.coordinate))
                        .frame(height: 200)
                        .glassCard(cornerRadius: 22, padding: 0)

                    GlassCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(distanceUnit.distanceString(meters: segment.lengthMeters))
                                    .font(AppFont.statValue(16))
                                    .foregroundStyle(AppColor.textPrimary)
                                Text("Oluşturan: \(segment.creatorNickname)")
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            Spacer()
                            Button {
                                Task { await vote() }
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: hasVoted ? "hand.thumbsup.fill" : "hand.thumbsup")
                                        .foregroundStyle(hasVoted ? AppColor.accent : AppColor.textSecondary)
                                    Text("\(voteCount)")
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.textSecondary)
                                }
                            }
                            .disabled(isVoting || !FeatureFlags.globalLeaderboardEnabled)
                        }
                    }
                    if !FeatureFlags.globalLeaderboardEnabled {
                        FeatureUnavailableCaption()
                    }

                    Button {
                        // Deliberately not also calling dismiss() here — it
                        // fought with the simultaneous tab switch to
                        // .dashboard (both tearing down this screen at once)
                        // and ended up swallowing the delayed isRecording
                        // flip in AppRootView.followSegment, so the drive
                        // never actually started. The tab switch alone
                        // already replaces this whole screen correctly.
                        onFollowSegment(segment)
                    } label: {
                        Label("Bu Rotayı Sür", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    .buttonStyle(.glass(.accent))

                    if isLoading {
                        ProgressView().tint(AppColor.accent).padding(.top, 40)
                    } else if entries.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                SegmentEffortRow(rank: index + 1, effort: entry, avatar: photoCache.image(for: entry.userId))
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(segment.name)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await load() }
        .alert(
            "Bir Sorun Oluştu",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("Tamam") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        #if DEBUG
        .task {
            // Test-only: fills the leaderboard with synthetic entries so
            // the ranked-list + #1 flame effect can be checked visually
            // without needing several real CloudKit accounts to race each
            // other. Overwrites load()'s real fetch shortly after it lands.
            guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedFakeLeaderboard") else { return }
            try? await Task.sleep(for: .milliseconds(600))
            let names = ["turbo", "al2", "crn", "max", "rex", "zed"]
            isLoading = false
            entries = names.enumerated().map { index, name in
                SegmentEffort(
                    id: "fake-\(index)",
                    segmentId: segment.id,
                    userId: "fake-user-\(index)",
                    nickname: name,
                    durationSeconds: Double(38 + index * 7),
                    averageSpeedKph: Double(65 - index * 3),
                    topSpeedKph: Double(95 - index * 2),
                    drivingScore: max(40, 100 - index * 8),
                    createdAt: Date()
                )
            }
        }
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.textTertiary)
            Text("Bu parkurda henüz kimse yok")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Bu rotayı sür, otomatik olarak liderlik tablosuna gönderilsin.")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 60)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let entriesResult = CloudKitSegmentService.fetchLeaderboard(segmentId: segment.id)
            let userId = try? await CloudKitSegmentService.currentUserId()
            myUserId = userId
            entries = try await entriesResult
            if let userId {
                hasVoted = (try? await CloudKitSegmentService.hasVoted(segmentId: segment.id, userId: userId)) ?? false
            }
            await photoCache.prefetch(userIds: entries.map(\.userId))
        } catch SegmentServiceError.featureNotAvailable {
            // Expected right now — CloudKit is gated off pending a paid
            // Apple Developer account (see FeatureFlags). Not a real
            // problem, so this falls through to the plain "no one yet"
            // empty state instead of a blocking alert — which, on this
            // screen, was covering the "Bu Rotayı Sür" button underneath it
            // the instant the screen opened.
        } catch {
            errorMessage = "Liderlik tablosu yüklenemedi. iCloud'a giriş yaptığından emin ol."
        }
    }

    private func vote() async {
        guard let myUserId else { return }
        isVoting = true
        defer { isVoting = false }
        do {
            if hasVoted {
                try await CloudKitSegmentService.unvoteSegment(segmentId: segment.id, userId: myUserId)
                hasVoted = false
                voteCount = max(0, voteCount - 1)
            } else {
                try await CloudKitSegmentService.voteForSegment(segmentId: segment.id, userId: myUserId)
                hasVoted = true
                voteCount += 1
            }
        } catch SegmentServiceError.featureNotAvailable {
            errorMessage = "Bu özellik yakında aktif olacak."
        } catch {
            // Was a hardcoded "check your connection" regardless of the
            // real reason — showed that even when genuinely connected,
            // masking whatever CKError (or, more likely, the voteCount
            // race adjustVoteCount now retries) actually happened.
            errorMessage = error.localizedDescription
        }
    }
}
