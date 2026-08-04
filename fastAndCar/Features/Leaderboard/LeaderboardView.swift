//
//  LeaderboardView.swift
//  fastAndCar
//
//  Ranked list for this trip's auto-detected route segment (same start/end
//  area, matched purely by rounded coordinates — no manual naming). Anyone
//  who submits a run on a matching segment shows up here, route line and
//  all.
//

import SwiftUI

struct LeaderboardView: View {
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var nicknameStore = NicknameStore()
    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showsNicknamePrompt = false

    private var segmentKey: String { SegmentKey.make(for: trip) ?? "" }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                if isLoading {
                    ProgressView().tint(AppColor.accent)
                } else if entries.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                LeaderboardRow(rank: index + 1, entry: entry)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Liderlik Tablosu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(AppColor.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        submit()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Label("Gönder", systemImage: "paperplane.fill")
                        }
                    }
                    .foregroundStyle(AppColor.accent)
                    .disabled(isSubmitting)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
        .sheet(isPresented: $showsNicknamePrompt) {
            NicknamePromptView(nicknameStore: nicknameStore) {
                submit()
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

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.textTertiary)
            Text("Bu rotada henüz kimse yok")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("İlk sen gönder, liderlik tablosunu başlat.")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 100)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await CloudKitLeaderboardService.fetchLeaderboard(segmentKey: segmentKey)
        } catch {
            errorMessage = "Liderlik tablosu yüklenemedi. iCloud'a giriş yaptığından emin ol."
        }
    }

    private func submit() {
        guard nicknameStore.hasNickname else {
            showsNicknamePrompt = true
            return
        }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await CloudKitLeaderboardService.submit(trip: trip, segmentKey: segmentKey, nickname: nicknameStore.nickname)
                entries = try await CloudKitLeaderboardService.fetchLeaderboard(segmentKey: segmentKey)
            } catch LeaderboardServiceError.notSignedIntoiCloud {
                errorMessage = "Liderlik tablosunu kullanmak için cihazında iCloud hesabına giriş yapmalısın."
            } catch {
                errorMessage = "Gönderilemedi. Bağlantını kontrol edip tekrar dene."
            }
        }
    }
}
