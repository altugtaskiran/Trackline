//
//  CrewInvitesInboxView.swift
//  fastAndCar
//
//  Pending "join my crew" requests addressed to this user (see
//  CrewInviteRequest) — the receiving side of CrewInviteByNameView's
//  name-search invite. Accepting calls CloudKitCrewService.acceptInviteRequest,
//  which fetches CKShare metadata purely through the CloudKit API, never
//  through a tapped link.
//

import SwiftUI

struct CrewInvitesInboxView: View {
    var onAccepted: (Crew, CrewZoneRef) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var invites: [CrewInviteRequest] = []
    @State private var isLoading = true
    @State private var respondingId: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        if isLoading {
                            ProgressView().tint(AppColor.accent).padding(.top, 40)
                        } else if invites.isEmpty {
                            emptyState
                        } else {
                            ForEach(invites) { invite in
                                GlassCard {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(invite.crewName)
                                                .font(AppFont.headline)
                                                .foregroundStyle(AppColor.textPrimary)
                                            Text("\(invite.fromNickname) davet etti")
                                                .font(AppFont.caption)
                                                .foregroundStyle(AppColor.textSecondary)
                                        }
                                        Spacer()
                                        if respondingId == invite.id {
                                            ProgressView()
                                        } else {
                                            HStack(spacing: 10) {
                                                Button {
                                                    Task { await respond(invite, accept: false) }
                                                } label: {
                                                    Image(systemName: "xmark")
                                                }
                                                .buttonStyle(.glass(.destructive))

                                                Button {
                                                    Task { await respond(invite, accept: true) }
                                                } label: {
                                                    Image(systemName: "checkmark")
                                                }
                                                .buttonStyle(.glass(.accent))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Davetler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
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
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.textTertiary)
            Text("Bekleyen davetin yok")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(.top, 60)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let userId = try await CloudKitCrewService.currentUserId()
            invites = try await CloudKitCrewService.fetchPendingInvites(userId: userId)
        } catch CrewServiceError.featureNotAvailable {
            // Not a real error — falls through to the empty state.
        } catch {
            errorMessage = "Davetler yüklenemedi. Bağlantını kontrol edip tekrar dene."
        }
    }

    private func respond(_ invite: CrewInviteRequest, accept: Bool) async {
        respondingId = invite.id
        defer { respondingId = nil }
        do {
            if accept {
                let userId = try await CloudKitCrewService.currentUserId()
                let nickname = NicknameStore().nickname
                let (crew, zoneRef) = try await CloudKitCrewService.acceptInviteRequest(invite, userId: userId, nickname: nickname)
                onAccepted(crew, zoneRef)
            } else {
                try await CloudKitCrewService.declineInviteRequest(invite)
            }
            invites.removeAll { $0.id == invite.id }
        } catch {
            // TEMPORARY debug surfacing — same technique as Settings'
            // nickname sync, to see the real CKError instead of a generic
            // message.
            errorMessage = accept ? "Davet kabul edilemedi. Bağlantını kontrol edip tekrar dene." : "İşlem tamamlanamadı."
        }
    }
}
