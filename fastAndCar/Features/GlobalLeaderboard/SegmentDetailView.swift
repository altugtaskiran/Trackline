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
                    RouteCanvas(samples: previewSamples, lineWidth: 3, showsEndpoints: true, padding: 20)
                        .frame(height: 200)
                        .glassCard(cornerRadius: 22, padding: 0)

                    GlassCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(format: "%.1f km", segment.lengthMeters / 1000))
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
                            .disabled(hasVoted || isVoting)
                        }
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
                                SegmentEffortRow(rank: index + 1, effort: entry)
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
        } catch SegmentServiceError.featureNotAvailable {
            errorMessage = "Bu özellik yakında aktif olacak."
        } catch {
            errorMessage = "Liderlik tablosu yüklenemedi. iCloud'a giriş yaptığından emin ol."
        }
    }

    private func vote() async {
        guard let myUserId else { return }
        isVoting = true
        defer { isVoting = false }
        do {
            try await CloudKitSegmentService.voteForSegment(segmentId: segment.id, userId: myUserId)
            hasVoted = true
            voteCount += 1
        } catch SegmentServiceError.featureNotAvailable {
            errorMessage = "Bu özellik yakında aktif olacak."
        } catch {
            errorMessage = "Oy verilemedi. Bağlantını kontrol edip tekrar dene."
        }
    }
}
