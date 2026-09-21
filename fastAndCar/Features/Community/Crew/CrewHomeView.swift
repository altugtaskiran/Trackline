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
    var onFollowCrewSegment: (Segment, CrewZoneRef) -> Void

    @State private var myCrewsStore = MyCrewsStore()
    @State private var showsCreateCrew = false
    @State private var showsInvite = false
    @State private var pendingShare: (share: CKShareBox, container: CKContainerBox)?
    @State private var pendingCrewName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if myCrewsStore.crews.isEmpty {
                            emptyState
                        } else {
                            ForEach(myCrewsStore.crews) { ref in
                                NavigationLink {
                                    CrewDetailView(crewRef: ref, onFollowCrewSegment: onFollowCrewSegment)
                                } label: {
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
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsCreateCrew) {
            CreateCrewView { ref, share in
                myCrewsStore.record(ref.crew, zoneRef: ref.zoneRef)
                pendingCrewName = ref.crew.name
                pendingShare = (CKShareBox(share), CKContainerBox(CKContainer.default()))
                showsInvite = true
            }
        }
        .sheet(isPresented: $showsInvite) {
            if let pendingShare {
                CrewInviteView(crewName: pendingCrewName, share: pendingShare.share.value, container: pendingShare.container.value)
            }
        }
        .onChange(of: CrewInviteAcceptance.shared.lastAcceptedCrew?.id) { _, _ in
            myCrewsStore = MyCrewsStore()
        }
        .onAppear {
            // Reload from disk every time this list becomes visible again —
            // covers popping back after leaving/deleting a crew in
            // CrewDetailView, whose own MyCrewsStore() instance is separate
            // from this one's in-memory copy.
            myCrewsStore = MyCrewsStore()
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
