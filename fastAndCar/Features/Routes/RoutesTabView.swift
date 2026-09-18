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

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if localRoutesStore.routes.isEmpty {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Rotalarım")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                            ForEach(localRoutesStore.routes) { segment in
                                // Pushed onto AppRootView's single shared
                                // NavigationStack (via .navigationDestination
                                // (for: Segment.self) there) rather than a
                                // NavigationStack owned by this view — a
                                // nested stack's push isn't reliably torn
                                // down just because this tab's own
                                // `selectedTab` switches away from it.
                                NavigationLink(value: segment) {
                                    SegmentRow(name: segment.name, subtitle: String(format: "%.1f km", segment.lengthMeters / 1000))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        showsTripPicker = true
                    } label: {
                        Label("Sürüşten Rota Oluştur", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.glass(.accent))
                }
                .padding(20)
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
