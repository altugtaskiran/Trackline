//
//  PublicProfileView.swift
//  fastAndCar
//
//  Opened by tapping a name on a leaderboard row (Global or Crew). Mirrors
//  ProfileView's own layout (name, totals, garage) but reads from that
//  person's synced UserProfile record (CloudKitProfileService.syncStats)
//  instead of local SwiftData — their device is the only one with the real
//  data, so this is only as fresh as their last sync. Also the entry point
//  for inviting *this specific* person into a crew you manage — found them
//  on a route's leaderboard, invite them straight from here instead of
//  hunting their nickname down separately.
//

import CloudKit
import SwiftUI

struct PublicProfileView: View {
    let userId: String
    let nickname: String

    @Environment(\.dismiss) private var dismiss
    @State private var photoCache = ProfilePhotoCache.shared
    @State private var stats: CloudKitProfileService.ProfileStats?
    @State private var isLoading = true
    @State private var myCrews = MyCrewsStore().crews
    @State private var pendingInviteShare: CKShareBox?
    @State private var inviteCrewName = ""
    @State private var inviteCrewId = ""
    @State private var errorMessage: String?
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault }

    private var ownedCrews: [MyCrewRef] {
        myCrews.filter(\.zoneRef.isOwnedByThisDevice)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        header
                        if let stats {
                            statsRow(stats)
                            if !stats.carSummaries.isEmpty {
                                garageSection(stats)
                            }
                        } else if isLoading {
                            ProgressView()
                                .tint(AppColor.accent)
                                .padding(.top, 24)
                        } else {
                            Text("Bu kullanıcı henüz istatistiklerini paylaşmamış.")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                                .padding(.top, 24)
                        }
                        if !ownedCrews.isEmpty {
                            inviteSection
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(AppColor.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $pendingInviteShare) { box in
            CrewInviteByNameView(crewId: inviteCrewId, crewName: inviteCrewName, share: box.value, presetUserId: userId, presetHandle: nickname)
        }
        .alert(
            "Bir Sorun Oluştu",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("Tamam") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            async let photos: () = photoCache.prefetch(userIds: [userId])
            async let fetchedStats = try? CloudKitProfileService.fetchStats(userIds: [userId])
            let result = await fetchedStats
            _ = await photos
            stats = result?[userId]
            isLoading = false
        }
    }

    private var header: some View {
        GlassCard {
            HStack(spacing: 14) {
                AvatarView(image: photoCache.image(for: userId), initial: nickname.first, size: 56)
                Text(nickname)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
            }
        }
    }

    private func statsRow(_ stats: CloudKitProfileService.ProfileStats) -> some View {
        HStack(spacing: 12) {
            statTile(title: "Toplam Mesafe", value: distanceUnit.distanceString(meters: stats.totalDistanceMeters), icon: "point.topleft.down.curvedto.point.bottomright.up", tint: AppColor.accent)
            statTile(title: "Sürüş Sayısı", value: "\(stats.tripCount)", icon: "flag.checkered", tint: Color(hex: 0x2E86FF))
            statTile(title: "Toplam Süre", value: formatDuration(stats.totalDriveTime), icon: "clock.fill", tint: Color(hex: 0xFF9100))
        }
    }

    private func statTile(title: LocalizedStringKey, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(AppFont.statValue(16))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: 14, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18, padding: 14)
    }

    private func garageSection(_ stats: CloudKitProfileService.ProfileStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Garaj")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            ForEach(Array(stats.carSummaries.enumerated()), id: \.offset) { index, summary in
                GlassCard {
                    HStack(spacing: 12) {
                        let photoData = index < stats.carPhotos.count ? stats.carPhotos[index] : nil
                        Group {
                            if let photoData, let uiImage = UIImage(data: photoData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                ZStack {
                                    AppColor.surfaceElevated
                                    Image(systemName: "car.fill")
                                        .foregroundStyle(AppColor.textTertiary)
                                }
                            }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Text(summary)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                    }
                }
            }
        }
    }

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Crew'a Davet Et")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("\(nickname), yönettiğin crew'a katılsın.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            ForEach(ownedCrews) { ref in
                Button {
                    Task { await presentInvite(for: ref) }
                } label: {
                    GlassCard {
                        HStack {
                            Text(ref.crew.name)
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.textPrimary)
                            Spacer()
                            Image(systemName: "person.badge.plus")
                                .foregroundStyle(AppColor.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func presentInvite(for ref: MyCrewRef) async {
        do {
            let record = try await CKContainer.default().privateCloudDatabase.record(for: CKRecord.ID(recordName: ref.crew.id, zoneID: ref.zoneRef.zoneID))
            guard let shareReference = record.share else {
                errorMessage = "Davet linki bulunamadı."
                return
            }
            let share = try await CKContainer.default().privateCloudDatabase.record(for: shareReference.recordID)
            guard let ckShare = share as? CKShare else { return }
            inviteCrewId = ref.crew.id
            inviteCrewName = ref.crew.name
            pendingInviteShare = CKShareBox(ckShare)
        } catch {
            errorMessage = "Davet açılamadı."
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)s \(minutes)dk" : "\(minutes)dk"
    }
}
