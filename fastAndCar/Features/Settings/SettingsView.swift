//
//  SettingsView.swift
//  fastAndCar
//
//  Minimal by design: permission status, distance unit, app version. Reached
//  from a small icon on Home rather than a tab bar.
//

import PhotosUI
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SettingsViewModel
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.system.rawValue
    @State private var profilePhotoData: Data? = UserDefaults.standard.data(forKey: "profilePhotoData")
    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImageForCrop: IdentifiableImage?
    @State private var isUploadingPhoto = false
    @State private var nicknameStore = NicknameStore()
    @State private var didCopyHandle = false
    @State private var nicknameDraft = ""
    @State private var isSavingNickname = false
    @State private var isEditingNickname = false
    #if DEBUG
    @State private var debugAutoOpenLanguage = false
    #endif

    init(locationManager: LocationManager) {
        _viewModel = State(initialValue: SettingsViewModel(locationManager: locationManager))
    }

    private var distanceUnit: Binding<DistanceUnit> {
        Binding(
            get: { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault },
            set: { distanceUnitRaw = $0.rawValue }
        )
    }

    private var appLanguage: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: appLanguageRaw) ?? .system },
            set: { appLanguageRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
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
                                    Text("Profil Fotoğrafı")
                                        .font(AppFont.headline)
                                        .foregroundStyle(AppColor.textPrimary)
                                    Text("Liderlik tablolarında görünür")
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.textSecondary)
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
                                    }
                                }
                                Spacer()
                            }
                        }

                        GlassCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Konum İzni")
                                        .font(AppFont.headline)
                                        .foregroundStyle(AppColor.textPrimary)
                                    Text(viewModel.authorizationStatusText)
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.textSecondary)
                                }
                                Spacer()
                                Circle()
                                    .fill(viewModel.authorizationIsGranted ? AppColor.accent : Color(hex: 0xFF3B30))
                                    .frame(width: 10, height: 10)
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Mesafe Birimi")
                                    .font(AppFont.headline)
                                    .foregroundStyle(AppColor.textPrimary)
                                Picker("Mesafe Birimi", selection: distanceUnit) {
                                    ForEach(DistanceUnit.allCases) { unit in
                                        Text(unit.label).tag(unit)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }

                        GlassCard(padding: 0) {
                            NavigationLink {
                                LanguagePickerView(selection: appLanguage)
                            } label: {
                                HStack {
                                    Text("Dil")
                                        .font(AppFont.headline)
                                        .foregroundStyle(AppColor.textPrimary)
                                    Spacer()
                                    Text(appLanguage.wrappedValue.label)
                                        .font(AppFont.body)
                                        .foregroundStyle(AppColor.textSecondary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AppColor.textTertiary)
                                }
                                .padding(16)
                            }
                            .buttonStyle(.plain)
                        }

                        GlassCard {
                            HStack {
                                Text("Sürüm")
                                    .font(AppFont.body)
                                    .foregroundStyle(AppColor.textSecondary)
                                Spacer()
                                Text(viewModel.appVersion)
                                    .font(AppFont.body)
                                    .foregroundStyle(AppColor.textPrimary)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(AppColor.accent)
                }
            }
            #if DEBUG
            .navigationDestination(isPresented: $debugAutoOpenLanguage) {
                LanguagePickerView(selection: appLanguage)
            }
            #endif
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
        #if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoLanguage") else { return }
            try? await Task.sleep(for: .seconds(1))
            debugAutoOpenLanguage = true
        }
        #endif
    }

    private func saveNickname() async {
        let trimmed = nicknameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSavingNickname = true
        defer { isSavingNickname = false }
        let previous = nicknameStore.nickname
        nicknameStore.nickname = trimmed
        try? await CloudKitProfileService.syncHandle(nickname: trimmed, tag: nicknameStore.tag, previousNickname: previous)
    }
}
