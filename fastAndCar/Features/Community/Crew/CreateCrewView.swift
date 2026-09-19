//
//  CreateCrewView.swift
//  fastAndCar
//

import CloudKit
import SwiftUI

struct CreateCrewView: View {
    @Environment(\.dismiss) private var dismiss
    var onCreated: (MyCrewRef, CKShare) -> Void

    @State private var nicknameStore = NicknameStore()
    @State private var name = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showsNicknamePrompt = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                VStack(spacing: 20) {
                    Spacer()

                    Text("Crew'una bir isim ver")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)

                    TextField("örn. Cuma Konvoyu", text: $name)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColor.surfaceElevated))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button {
                        create()
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Oluştur ve Davet Et")
                        }
                    }
                    .buttonStyle(.glass(.accent))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating || !FeatureFlags.crewEnabled)

                    if !FeatureFlags.crewEnabled {
                        FeatureUnavailableCaption()
                    }

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
        .sheet(isPresented: $showsNicknamePrompt) {
            NicknamePromptView(nicknameStore: nicknameStore) {
                create()
            }
        }
        .alert(
            "Bir Sorun Oluştu",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("Tamam") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func create() {
        guard nicknameStore.hasNickname else {
            showsNicknamePrompt = true
            return
        }
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                let userId = try await CloudKitCrewService.currentUserId()
                let trimmedName = name.trimmingCharacters(in: .whitespaces)
                let (crew, share, zoneRef) = try await CloudKitCrewService.createCrew(
                    name: trimmedName,
                    creatorId: userId,
                    creatorNickname: nicknameStore.nickname
                )
                onCreated(MyCrewRef(crew: crew, zoneRef: zoneRef), share)
                dismiss()
            } catch CrewServiceError.featureNotAvailable {
                errorMessage = "Bu özellik yakında aktif olacak."
            } catch CrewServiceError.notSignedIntoiCloud {
                errorMessage = "Crew oluşturmak için cihazında iCloud hesabına giriş yapmalısın."
            } catch {
                errorMessage = "Crew oluşturulamadı. Bağlantını kontrol edip tekrar dene."
            }
        }
    }
}
