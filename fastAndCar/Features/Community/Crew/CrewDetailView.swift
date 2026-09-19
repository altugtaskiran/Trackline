//
//  CrewDetailView.swift
//  fastAndCar
//
//  Member roster + a per-member personal-best ranking (best driving score
//  each member has posted) rather than a raw, ever-growing feed of every
//  single drive — a Crew is comparing who's driving well, not scrolling
//  through a timeline. Recent drives still show below for the "did anyone
//  do anything lately" glance, each deletable by whoever posted it.
//

import CloudKit
import SwiftUI

private struct MemberRanking: Identifiable {
    let userId: String
    let nickname: String
    let bestScore: Int
    let bestTopSpeedKph: Double
    var id: String { userId }
}

struct CrewDetailView: View {
    let crewRef: MyCrewRef

    @Environment(\.dismiss) private var dismiss
    @State private var members: [CrewMembership] = []
    @State private var summaries: [CrewDriveSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showsInvite = false
    @State private var pendingShare: (share: CKShareBox, container: CKContainerBox)?
    @State private var myUserId: String?
    @State private var isLeaving = false

    private var rankings: [MemberRanking] {
        let grouped = Dictionary(grouping: summaries, by: \.userId)
        return grouped.compactMap { userId, entries in
            guard let nickname = entries.first?.nickname,
                  let bestScore = entries.map(\.drivingScore).max(),
                  let bestTopSpeedKph = entries.map(\.topSpeedKph).max() else { return nil }
            return MemberRanking(userId: userId, nickname: nickname, bestScore: bestScore, bestTopSpeedKph: bestTopSpeedKph)
        }
        .sorted { $0.bestScore > $1.bestScore }
    }

    private var recentSummaries: [CrewDriveSummary] {
        Array(summaries.sorted { $0.createdAt > $1.createdAt }.prefix(10))
    }

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

                        if summaries.isEmpty {
                            emptyState
                        } else {
                            rankingSection
                            recentSection
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

    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Crew Sıralaması")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            LazyVStack(spacing: 12) {
                ForEach(Array(rankings.enumerated()), id: \.element.id) { index, ranking in
                    HStack(spacing: 14) {
                        Text("#\(index + 1)")
                            .font(AppFont.statValue(16))
                            .foregroundStyle(index == 0 ? AppColor.accent : AppColor.textSecondary)
                            .frame(width: 34, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ranking.nickname)
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                            Text("Zirve \(Int(ranking.bestTopSpeedKph)) km/h")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        Spacer()
                        Text("\(ranking.bestScore)")
                            .font(AppFont.statValue(18))
                            .foregroundStyle(AppColor.accent)
                    }
                    .glassCard(cornerRadius: 18, padding: 14)
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Son Sürüşler")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            LazyVStack(spacing: 12) {
                ForEach(recentSummaries) { summary in
                    HStack(spacing: 0) {
                        CrewDriveSummaryRow(summary: summary)
                        if summary.userId == myUserId {
                            Button {
                                Task { await deleteSummary(summary) }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(AppColor.textTertiary)
                            }
                            .padding(.leading, 10)
                        }
                    }
                }
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
            Image(systemName: "person.3")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.textTertiary)
            Text("Henüz paylaşılan sürüş yok")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Bir sürüş bitirip paylaşırken bu crew ile paylaşmayı seçersen burada görünür.")
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
            async let summariesResult = CloudKitCrewService.fetchDriveSummaries(zoneRef: crewRef.zoneRef)
            members = try await membersResult
            summaries = try await summariesResult
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

    private func deleteSummary(_ summary: CrewDriveSummary) async {
        do {
            try await CloudKitCrewService.deleteDriveSummary(id: summary.id, zoneRef: crewRef.zoneRef)
            summaries.removeAll { $0.id == summary.id }
        } catch CrewServiceError.featureNotAvailable {
            errorMessage = "Bu özellik yakında aktif olacak."
        } catch {
            errorMessage = "Silinemedi."
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
