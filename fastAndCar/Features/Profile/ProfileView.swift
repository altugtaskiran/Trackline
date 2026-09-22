//
//  ProfileView.swift
//  fastAndCar
//
//  Opened from the round avatar next to "Sürüşlerim" — a quick summary of
//  this device's own identity: total distance/trip count (local SwiftData,
//  same source TripsListView already queries) and the Garage roster.
//  Crew invites live on PublicProfileView now (invite *that* specific
//  person you just found), not here — the Crew screen's own leaderboard
//  already covers "invite anyone" for a crew you manage.
//

import PhotosUI
import SwiftData
import SwiftUI

struct ProfileView: View {
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \Car.createdAt) private var cars: [Car]

    @Environment(\.dismiss) private var dismiss
    @State private var nicknameStore = NicknameStore()
    @State private var profilePhotoData: Data? = UserDefaults.standard.data(forKey: "profilePhotoData")
    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImageForCrop: IdentifiableImage?
    @State private var isUploadingPhoto = false
    @State private var didCopyHandle = false
    @State private var nicknameDraft = ""
    @State private var isSavingNickname = false
    @State private var isEditingNickname = false
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault }

    private var totalDistanceMeters: Double { trips.reduce(0) { $0 + $1.distanceMeters } }
    private var totalDriveTime: TimeInterval { trips.reduce(0) { $0 + $1.driveTime } }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        header
                        statsRow
                        if !cars.isEmpty {
                            garageSection
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
        .task(id: photoItem) {
            guard let photoItem,
                  let data = try? await photoItem.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else { return }
            try? await Task.sleep(for: .milliseconds(250))
            pickedImageForCrop = IdentifiableImage(image: uiImage)
        }
        .sheet(item: $pickedImageForCrop) { wrapped in
            PhotoCropView(image: wrapped.image, aspectRatio: 1) { croppedData in
                profilePhotoData = croppedData
                UserDefaults.standard.set(croppedData, forKey: "profilePhotoData")
                Task {
                    isUploadingPhoto = true
                    defer { isUploadingPhoto = false }
                    try? await CloudKitProfileService.uploadMyPhoto(data: croppedData)
                }
            }
        }
        .task {
            // Best-effort — keeps the public UserProfile record (what other
            // users see via PublicProfileView) fresh even if a car got
            // added/edited since the last trip ended.
            let carEntries = cars.map { CloudKitProfileService.CarSyncEntry(name: "\($0.year) \($0.displayName)", photoData: $0.photoData) }
            try? await CloudKitProfileService.syncStats(
                totalDistanceMeters: totalDistanceMeters,
                tripCount: trips.count,
                totalDriveTime: totalDriveTime,
                cars: carEntries
            )
        }
    }

    private var header: some View {
        GlassCard {
            HStack(spacing: 14) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ZStack {
                        AvatarView(image: profilePhotoData.flatMap(UIImage.init), initial: nil, size: 56)
                        if isUploadingPhoto {
                            ProgressView().tint(AppColor.accent)
                        }
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    if !isEditingNickname {
                        Text(nicknameStore.hasNickname ? nicknameStore.nickname : "İsimsiz Sürücü")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    if isEditingNickname {
                        HStack(spacing: 8) {
                            TextField("kullanıcı adı", text: $nicknameDraft)
                                .font(AppFont.caption.weight(.semibold))
                                .foregroundStyle(AppColor.textPrimary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppColor.surfaceElevated))
                            Button {
                                Task {
                                    await saveNickname()
                                    isEditingNickname = false
                                }
                            } label: {
                                if isSavingNickname {
                                    ProgressView()
                                } else {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .disabled(isSavingNickname || nicknameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .foregroundStyle(AppColor.accent)
                    } else if nicknameStore.hasNickname {
                        HStack(spacing: 8) {
                            Button {
                                UIPasteboard.general.string = nicknameStore.handle
                                didCopyHandle = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text(nicknameStore.handle)
                                    Image(systemName: didCopyHandle ? "checkmark" : "doc.on.doc")
                                }
                            }
                            Button {
                                nicknameDraft = nicknameStore.nickname
                                isEditingNickname = true
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .padding(.leading, 10)
                        }
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColor.accent)
                    } else {
                        Button {
                            nicknameDraft = ""
                            isEditingNickname = true
                        } label: {
                            Text("İsim Ekle")
                        }
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColor.accent)
                    }
                }
                Spacer()
            }
        }
    }

    private func saveNickname() async {
        let trimmed = nicknameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSavingNickname = true
        defer { isSavingNickname = false }
        let previous = nicknameStore.nickname
        nicknameStore.nickname = trimmed
        try? await CloudKitProfileService.syncHandle(nickname: trimmed, tag: nicknameStore.tag, previousNickname: previous)

        // Best-effort cascade — otherwise every leaderboard row and crew
        // roster entry written before this rename keeps showing the old
        // name forever (confirmed live). Never blocks the UI on failure.
        guard let userId = try? await CloudKitSegmentService.currentUserId() else { return }
        Task {
            try? await CloudKitSegmentService.updateMyNicknameOnEfforts(userId: userId, nickname: trimmed)
            for crewRef in MyCrewsStore().crews {
                try? await CloudKitCrewService.updateMyNickname(userId: userId, nickname: trimmed, zoneRef: crewRef.zoneRef)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            profileStatTile(title: "Toplam Mesafe", value: distanceUnit.distanceString(meters: totalDistanceMeters), icon: "point.topleft.down.curvedto.point.bottomright.up", tint: AppColor.accent)
            profileStatTile(title: "Sürüş Sayısı", value: "\(trips.count)", icon: "flag.checkered", tint: Color(hex: 0x2E86FF))
            profileStatTile(title: "Toplam Süre", value: formatDuration(totalDriveTime), icon: "clock.fill", tint: Color(hex: 0xFF9100))
        }
    }

    private func profileStatTile(title: LocalizedStringKey, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(AppFont.statValue(16))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // Fixed-height title line (lineLimit + fixed frame, not just
            // minimumScaleFactor) so a two-line title like "Toplam Mesafe"
            // can't make its card taller than its neighbors — otherwise the
            // three cards visibly don't line up.
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

    private var garageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Garaj")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            ForEach(cars) { car in
                CarCard(car: car, onEdit: {}, onDelete: {})
                    .allowsHitTesting(false)
            }
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)s \(minutes)dk" : "\(minutes)dk"
    }
}
