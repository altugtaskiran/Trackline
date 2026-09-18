//
//  TripsListView.swift
//  fastAndCar
//
//  The "Sürüşlerim" tab: trip history. Start Drive itself now lives on the
//  Dashboard tab — this is history + settings only.
//

import SwiftData
import SwiftUI

struct TripsListView: View {
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @State private var showsSettings = false
    @State private var showsAchievements = false
    @Environment(\.modelContext) private var modelContext
    private let locationManager: LocationManager

    var onSelectTrip: (Trip) -> Void

    init(locationManager: LocationManager, onSelectTrip: @escaping (Trip) -> Void) {
        self.locationManager = locationManager
        self.onSelectTrip = onSelectTrip
    }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                if trips.isEmpty {
                    ScrollView {
                        emptyState
                    }
                } else {
                    List {
                        ForEach(trips) { trip in
                            Button {
                                onSelectTrip(trip)
                            } label: {
                                TripRowCard(trip: trip)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 14, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation { modelContext.delete(trip) }
                                } label: {
                                    Label("Sil", systemImage: "trash")
                                }
                            }
                        }
                        Color.clear
                            .frame(height: 20)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(locationManager: locationManager)
        }
        .sheet(isPresented: $showsAchievements) {
            AchievementsView()
        }
        #if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoSettings") else { return }
            try? await Task.sleep(for: .seconds(1))
            showsSettings = true
        }
        #endif
    }

    private var header: some View {
        HStack {
            Text("Sürüşlerim")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            Button {
                showsAchievements = true
            } label: {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 36, height: 36)
            }
            Button {
                showsSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 36, height: 36)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            RouteMotifShape()
                .stroke(AppColor.textTertiary, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(height: 140)
                .padding(.horizontal, 32)

            Text("Henüz yolculuk yok")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("İlk sürüşünü başlat, rotanı burada gör.")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.top, 80)
    }
}
