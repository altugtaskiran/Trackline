//
//  CrewHomeView.swift
//  fastAndCar
//
//  My crews (created or joined — see MyCrewsStore) + create. Joining an
//  existing crew has no separate screen here: accepting a CKShare invite
//  link is what adds it, handled by CrewShareAppDelegate the moment iOS
//  hands the tapped link to the app.
//

import CloudKit
import SwiftUI

struct CrewHomeView: View {
    var onFollowCrewSegment: (Segment, String, CrewZoneRef) -> Void

    @State private var myCrewsStore = MyCrewsStore()
    @State private var showsCreateCrew = false
    @State private var showsInvite = false
    @State private var showsInvitesInbox = false
    @State private var pendingShare: (share: CKShareBox, container: CKContainerBox)?
    @State private var pendingCrewName = ""
    @State private var pendingInviteCount = 0

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if pendingInviteCount > 0 {
                        Button {
                            showsInvitesInbox = true
                        } label: {
                            Label("Bekleyen Davetler (\(pendingInviteCount))", systemImage: "tray.full.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass(.accent))
                    }

                    if myCrewsStore.crews.isEmpty {
                        emptyState
                    } else {
                        ForEach(myCrewsStore.crews) { ref in
                            NavigationLink(value: ref) {
                                CrewRow(name: ref.crew.name, subtitle: ref.zoneRef.isOwnedByThisDevice ? "Kurucu sensin" : "Üyesin")
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        showsCreateCrew = true
                    } label: {
                        Label("Yeni Crew Oluştur", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.glass(.accent))
                }
                .padding(20)
            }
        }
        .navigationTitle("Crew")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsCreateCrew) {
            // QR/link invite (showsInvite/CrewInviteView) is deactivated —
            // just record the crew now; inviting happens from
            // CrewDetailView's by-name search instead.
            CreateCrewView { ref, _ in
                myCrewsStore.record(ref.crew, zoneRef: ref.zoneRef)
            }
        }
        .sheet(isPresented: $showsInvite) {
            if let pendingShare {
                CrewInviteView(crewName: pendingCrewName, share: pendingShare.share.value, container: pendingShare.container.value)
            }
        }
        .sheet(isPresented: $showsInvitesInbox) {
            CrewInvitesInboxView { crew, zoneRef in
                myCrewsStore.record(crew, zoneRef: zoneRef)
            }
        }
        .onChange(of: CrewInviteAcceptance.shared.lastAcceptedCrew?.id) { _, _ in
            myCrewsStore = MyCrewsStore()
        }
        .onChange(of: showsInvitesInbox) { wasShowing, isShowing in
            if wasShowing, !isShowing { Task { await loadPendingInviteCount() } }
        }
        .onAppear {
            // Reload from disk every time this list becomes visible again —
            // covers popping back after leaving/deleting a crew in
            // CrewDetailView, whose own MyCrewsStore() instance is separate
            // from this one's in-memory copy.
            myCrewsStore = MyCrewsStore()
            Task { await loadPendingInviteCount() }
        }
        #if DEBUG
        .task {
            // Test-only hook: seeds a fake local crew so CrewDetailView's
            // roster/ranking/leave UI can be screenshotted without a live
            // CloudKit round trip.
            guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedFakeCrew") else { return }
            let fakeCrew = Crew(id: "fake-crew", name: "Cuma Konvoyu", creatorId: "me", creatorNickname: "Sen", createdAt: Date())
            let fakeZoneRef = CrewZoneRef(zoneName: "fake-zone", ownerName: nil)
            myCrewsStore.record(fakeCrew, zoneRef: fakeZoneRef)
        }
        #endif
    }

    private func loadPendingInviteCount() async {
        guard FeatureFlags.crewEnabled else { return }
        guard let userId = try? await CloudKitCrewService.currentUserId() else { return }
        pendingInviteCount = (try? await CloudKitCrewService.fetchPendingInvites(userId: userId).count) ?? 0
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.3")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.textTertiary)
            Text("Henüz bir crew'un yok")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Bir crew oluştur ve arkadaşlarını davet et — sürüşlerinizi karşılaştırın, konum paylaşımı olmadan.")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
