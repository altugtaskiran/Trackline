//
//  RoutesTabView.swift
//  fastAndCar
//
//  "Rotalar" tab — your own saved drives, turned into routes you (and once
//  CloudKit's active, other people) can follow again. Deliberately not the
//  Global Leaderboard's segment search: this is "my routes", not "discover
//  anyone's route by name" — that's what Liderlik's Global section is for.
//

import SwiftUI

struct RoutesTabView: View {
    var onFollowSegment: (Segment) -> Void

    @State private var localRoutesStore = LocalRoutesStore()
    @State private var showsTripPicker = false
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Button {
                    showsTripPicker = true
                } label: {
                    Label("Sürüşten Rota Oluştur", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.glass(.accent))
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if localRoutesStore.routes.isEmpty {
                    ScrollView {
                        emptyState
                            .padding(20)
                    }
                } else {
                    // List, not ScrollView+VStack — .swipeActions only
                    // attaches to List rows, and a route needs to be
                    // deletable from here.
                    List {
                        Section {
                            ForEach(localRoutesStore.routes) { segment in
                                // Pushed onto AppRootView's single shared
                                // NavigationStack (via .navigationDestination
                                // (for: Segment.self) there) rather than a
                                // NavigationStack owned by this view — a
                                // nested stack's push isn't reliably torn
                                // down just because this tab's own
                                // `selectedTab` switches away from it.
                                // SegmentRow already draws its own trailing
                                // chevron (shared with the non-List contexts
                                // it's also used in) — a visible
                                // NavigationLink(value:) { label } here would
                                // stack List's automatic disclosure
                                // indicator on top of that second one. The
                                // link is kept but made invisible/zero-size
                                // so SegmentRow's own chevron is the only one
                                // shown, while the whole row stays tappable.
                                SegmentRow(name: segment.name, subtitle: distanceUnit.distanceString(meters: segment.lengthMeters))
                                    .background(
                                        NavigationLink(value: segment) { EmptyView() }
                                            .opacity(0)
                                    )
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 10, trailing: 20))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        withAnimation { localRoutesStore.remove(segment.id) }
                                        // A route deleted here might also
                                        // have been published to the Global
                                        // Leaderboard (opt-in toggle in
                                        // CreateSegmentFlowView) — removing
                                        // it locally should take it off
                                        // there too, not leave a dangling
                                        // "Oluşturduklarım" entry pointing
                                        // at a route that no longer exists.
                                        // Harmless no-op if it was never
                                        // published.
                                        MyCreatedSegmentsStore().remove(segment.id)
                                        Task { try? await CloudKitSegmentService.deleteSegment(id: segment.id) }
                                    } label: {
                                        Label("Sil", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            Text("Rotalarım")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                                .textCase(nil)
                                .padding(.leading, 20)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Rotalar")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsTripPicker) {
            PickTripForRouteView()
        }
        .onChange(of: showsTripPicker) { _, isPresented in
            // Reloads from disk once the trip-picker/create-route sheet
            // dismisses — also picks up routes created elsewhere (e.g. Trip
            // Detail's own "Bu rotadan segment oluştur" ruler button).
            guard !isPresented else { return }
            localRoutesStore = LocalRoutesStore()
        }
        .onAppear {
            localRoutesStore = LocalRoutesStore()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "map")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.textTertiary)
            Text("Henüz bir rotan yok")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Kaydedilmiş bir sürüşten rota oluştur, sonra aynı rotayı tekrar sürmek için kullan.")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
