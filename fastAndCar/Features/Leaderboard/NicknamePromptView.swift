//
//  NicknamePromptView.swift
//  fastAndCar
//

import SwiftUI

struct NicknamePromptView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var nicknameStore: NicknameStore
    var onSaved: () -> Void

    @State private var draft = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                VStack(spacing: 20) {
                    Spacer()

                    Text("Liderlik tablosunda görünecek bir isim seç")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    TextField("örn. turbo_mert", text: $draft)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColor.surfaceElevated))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button("Kaydet") {
                        nicknameStore.nickname = draft.trimmingCharacters(in: .whitespaces)
                        let nickname = nicknameStore.nickname
                        let tag = nicknameStore.tag
                        Task { try? await CloudKitProfileService.syncHandle(nickname: nickname, tag: tag) }
                        dismiss()
                        onSaved()
                    }
                    .buttonStyle(.glass(.accent))
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)

                    Spacer()
                }
                .padding(28)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
