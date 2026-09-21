//
//  CrewDetailView.swift
//  fastAndCar
//
//  Member roster + the routes this crew is racing — a route shared here
//  (from Trip Detail's "Bu rotadan parkur oluştur" flow) gets its own
//  crew-scoped leaderboard (CrewSegmentDetailView), the same "everyone
//  drives the same road, fastest time wins" mechanic as the public Global
//  Leaderboard, just private to this crew's own zone. Replaces the earlier
//  one-off "share a stat card" mechanic (CrewDriveSummary) — comparing a
//  single trip's numbers in isolation wasn't a race.
//

import CloudKit
import SwiftUI

struct CrewDetailView: View {
    let crewRef: MyCrewRef
    var onFollowCrewSegment: (Segment, CrewZoneRef) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var members: [CrewMembership] = []
    @State private var segments: [Segment] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showsInvite = false
    @State private var pendingShare: (share: CKShareBox, container: CKContainerBox)?
    @State private var myUserId: String?
    @State private var isLeaving = false
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if !FeatureFlags.crewEnabled {
                        FeatureUnavailableView()
                    } else if isLoading {
                        ProgressView().tint(AppColor.accent).padding(.top, 40)
                    } else {
                        memberRoster

                        if segments.isEmpty {
                            emptyState
                        } else {
                            routesSection
                        }

                        leaveOrDeleteButton
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(crewRef.crew.name)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task {
            guard FeatureFlags.crewEnabled else { return }
            myUserId = try? await CloudKitCrewService.currentUserId()
            await load()
        }
        .alert(
            "Bir Sorun Oluştu",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("Tamam") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showsInvite) {
            if let pendingShare {
                CrewInviteView(crewName: crewRef.crew.name, share: pendingShare.share.value, container: pendingShare.container.value)
            }
        }
    }

    private var header: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(members.count) üye")
                        .font(AppFont.statValue(16))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Kurucu: \(crewRef.crew.creatorNickname)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                if crewRef.zoneRef.isOwnedByThisDevice {
                    Button {
                        Task { await presentInvite() }
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .foregroundStyle(FeatureFlags.crewEnabled ? AppColor.accent : AppColor.textTertiary)
                    }
                    .disabled(!FeatureFlags.crewEnabled)
                }
            }
        }
    }

    private var memberRoster: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Üyeler")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            ForEach(members) { member in
                HStack {
                    Text(member.nickname)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    if crewRef.zoneRef.isOwnedByThisDevice, member.userId != myUserId {
                        Button {
                            Task { await removeMember(member) }
                        } label: {
                            Image(systemName: "person.badge.minus")
                                .foregroundStyle(Color(hex: 0xFF3B30))
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var routesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rotalar")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            ForEach(segments) { segment in
                NavigationLink {
                    CrewSegmentDetailView(segment: segment, zoneRef: crewRef.zoneRef, onFollowSegment: onFollowCrewSegment)
                } label: {
                    SegmentRow(name: segment.name, subtitle: distanceUnit.distanceString(meters: segment.lengthMeters))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var leaveOrDeleteButton: some View {
        Button(role: .destructive) {
            Task { await leave() }
        } label: {
            if isLeaving {
                ProgressView()
            } else {
                Text(crewRef.zoneRef.isOwnedByThisDevice ? "Crew'u Sil" : "Crew'dan Ayrıl")
            }
        }
        .buttonStyle(.glass(.destructive))
        .disabled(isLeaving)
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.textTertiary)
            Text("Henüz bir rota yok")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Bir sürüş detayında rotandan parkur oluştururken bu crew'a eklemeyi seçersen burada görünür.")
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
            async let membersResult = CloudKitCrewService.fetchMembers(zoneRef: crewRef.zoneRef)
            async let segmentsResult = CloudKitCrewService.fetchSegments(zoneRef: crewRef.zoneRef)
            members = try await membersResult
            segments = try await segmentsResult
        } catch CrewServiceError.featureNotAvailable {
            errorMessage = "Bu özellik yakında aktif olacak."
        } catch {
            errorMessage = "Crew bilgileri yüklenemedi. iCloud'a giriş yaptığından emin ol."
        }
    }

    private func presentInvite() async {
        do {
            let record = try await CKContainer.default().privateCloudDatabase.record(for: CKRecord.ID(recordName: crewRef.crew.id, zoneID: crewRef.zoneRef.zoneID))
            guard let shareReference = record.share else {
                errorMessage = "Davet linki bulunamadı."
                return
            }
            let share = try await CKContainer.default().privateCloudDatabase.record(for: shareReference.recordID)
            guard let ckShare = share as? CKShare else { return }
            pendingShare = (CKShareBox(ckShare), CKContainerBox(CKContainer.default()))
            showsInvite = true
        } catch {
            errorMessage = "Davet açılamadı."
        }
    }

    private func removeMember(_ member: CrewMembership) async {
        do {
            try await CloudKitCrewService.removeMember(crewId: crewRef.crew.id, userId: member.userId, zoneRef: crewRef.zoneRef)
            members.removeAll { $0.id == member.id }
        } catch CrewServiceError.featureNotAvailable {
            errorMessage = "Bu özellik yakında aktif olacak."
        } catch {
            errorMessage = "Üye çıkarılamadı."
        }
    }

    private func leave() async {
        isLeaving = true
        defer { isLeaving = false }
        do {
            try await CloudKitCrewService.leaveCrew(zoneRef: crewRef.zoneRef)
            MyCrewsStore().remove(crewRef.crew.id)
            dismiss()
        } catch CrewServiceError.featureNotAvailable {
            errorMessage = "Bu özellik yakında aktif olacak."
        } catch {
            errorMessage = "İşlem tamamlanamadı. Bağlantını kontrol edip tekrar dene."
        }
    }
}

/// CKShare/CKContainer aren't Equatable in a way SwiftUI's diffing loves —
/// boxing them keeps the sheet's optional state simple to update in one
/// assignment above.
struct CKShareBox { let value: CKShare; init(_ value: CKShare) { self.value = value } }
struct CKContainerBox { let value: CKContainer; init(_ value: CKContainer) { self.value = value } }
