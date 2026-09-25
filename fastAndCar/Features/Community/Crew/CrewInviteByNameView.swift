//
//  CrewInviteByNameView.swift
//  fastAndCar
//
//  Alternative to CrewInviteView's QR/link — search a friend by name and
//  send them an in-app request instead of a raw CKShare link, which
//  sidesteps iOS's unreliable system share-link handoff for an app not yet
//  on the App Store. Typing just a nickname (no #tag) looks up everyone
//  currently using that name; if more than one comes back, the sender picks
//  the right one from a list instead of needing the #tag up front.
//

import CloudKit
import SwiftUI

struct CrewInviteByNameView: View {
    let crewId: String
    let crewName: String
    let share: CKShare
    /// Set when opened from a specific person's profile (PublicProfileView)
    /// — that person is already known, so the search UI is skipped entirely
    /// and this goes straight to the "send" confirmation card.
    var presetUserId: String?
    var presetHandle: String?

    @Environment(\.dismiss) private var dismiss
    @State private var nicknameDraft = ""
    @State private var isSearching = false
    @State private var candidates: [(userId: String, tag: Int)] = []
    @State private var selected: (userId: String, handle: String)?
    @State private var searched = false
    @State private var isSending = false
    @State private var didSend = false
    @State private var errorMessage: String?
    @State private var photoCache = ProfilePhotoCache.shared

    private var typedNickname: String {
        nicknameDraft.trimmingCharacters(in: .whitespaces)
    }

    private var isPreset: Bool { presetUserId != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                VStack(spacing: 20) {
                    if !isPreset {
                        Text("Arkadaşının kullanıcı adını gir")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                            .multilineTextAlignment(.center)

                        TextField("örn. turbo (ya da turbo#4823)", text: $nicknameDraft)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColor.surfaceElevated))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .multilineTextAlignment(.center)
                            .onChange(of: nicknameDraft) { _, _ in
                                candidates = []
                                selected = nil
                                searched = false
                                didSend = false
                            }

                        Button {
                            Task { await search() }
                        } label: {
                            if isSearching {
                                ProgressView()
                            } else {
                                Text("Ara")
                            }
                        }
                        .buttonStyle(.glass(.neutral))
                        .disabled(isSearching || typedNickname.isEmpty)
                    }

                    if searched && candidates.isEmpty && selected == nil {
                        Text("Bu kullanıcı bulunamadı. Adı kontrol et.")
                            .font(AppFont.caption)
                            .foregroundStyle(Color(hex: 0xFF3B30))
                    }

                    // More than one person shares this nickname — pick
                    // which one (shown with their #tag to tell them apart).
                    if selected == nil, candidates.count > 1 {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Aynı isimde birden fazla kullanıcı var, birini seç:")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                            ForEach(candidates, id: \.userId) { candidate in
                                Button {
                                    selected = (candidate.userId, "\(typedNickname)#\(candidate.tag)")
                                } label: {
                                    HStack(spacing: 12) {
                                        AvatarView(image: photoCache.image(for: candidate.userId), initial: typedNickname.first, size: 36)
                                        Text("\(typedNickname)#\(candidate.tag)" as String)
                                            .foregroundStyle(AppColor.textPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(AppColor.textTertiary)
                                    }
                                }
                                .glassCard(cornerRadius: 14, padding: 14)
                            }
                        }
                    }

                    if let selected {
                        GlassCard {
                            HStack(spacing: 12) {
                                AvatarView(image: photoCache.image(for: selected.userId), initial: selected.handle.first, size: 40)
                                Text(selected.handle)
                                    .font(AppFont.headline)
                                    .foregroundStyle(AppColor.textPrimary)
                                Spacer()
                                if didSend {
                                    Label("Gönderildi", systemImage: "checkmark.circle.fill")
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.accent)
                                } else {
                                    Button {
                                        Task { await sendInvite() }
                                    } label: {
                                        if isSending {
                                            ProgressView()
                                        } else {
                                            Text("Davet Gönder")
                                        }
                                    }
                                    .buttonStyle(.glass(.accent))
                                    .disabled(isSending)
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .padding(28)
            }
            .navigationTitle(isPreset ? "Crew'a Davet Et" : "İsimle Davet Et")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
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
        .preferredColorScheme(.dark)
        .onAppear {
            if let presetUserId, let presetHandle, selected == nil {
                selected = (presetUserId, presetHandle)
                Task { await photoCache.prefetch(userIds: [presetUserId]) }
            }
        }
    }

    /// "turbo#4823" is still accepted as a shortcut straight to one exact
    /// person; plain "turbo" goes through the nickname-only lookup instead.
    private var parsedExactHandle: (nickname: String, tag: Int)? {
        let parts = typedNickname.split(separator: "#")
        guard parts.count == 2, let tag = Int(parts[1]), !parts[0].isEmpty else { return nil }
        return (String(parts[0]), tag)
    }

    private func search() async {
        guard !typedNickname.isEmpty else { return }
        isSearching = true
        searched = false
        candidates = []
        selected = nil
        defer { isSearching = false; searched = true }
        do {
            if let exact = parsedExactHandle {
                if let userId = try await CloudKitProfileService.findUser(nickname: exact.nickname, tag: exact.tag) {
                    selected = (userId, "\(exact.nickname)#\(exact.tag)")
                }
                return
            }

            let found = try await CloudKitProfileService.findUsers(byNickname: typedNickname)
            if found.count == 1, let only = found.first {
                selected = (only.userId, "\(typedNickname)#\(only.tag)")
            } else {
                candidates = found
            }
        } catch {
            errorMessage = "Arama yapılamadı. Bağlantını kontrol edip tekrar dene."
        }
        let userIds = (selected.map { [$0.userId] } ?? []) + candidates.map(\.userId)
        if !userIds.isEmpty {
            await photoCache.prefetch(userIds: userIds)
        }
    }

    private func sendInvite() async {
        guard let selected, let url = share.url else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await CloudKitCrewService.addParticipant(userId: selected.userId, to: share)
            try await CloudKitCrewService.sendInviteRequest(
                crewId: crewId,
                crewName: crewName,
                shareURL: url,
                fromNickname: NicknameStore().nickname,
                targetUserId: selected.userId
            )
            didSend = true
        } catch {
            errorMessage = "Davet gönderilemedi. Bağlantını kontrol edip tekrar dene."
        }
    }
}
