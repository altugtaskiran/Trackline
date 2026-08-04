//
//  HomeView.swift
//  fastAndCar
//
//  Trip history doubles as the home surface: a list of past drives plus one
//  floating "Start Drive" action. No tab bar, no extra chrome.
//

import SwiftData
import SwiftUI
import UIKit

struct HomeView: View {
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @State private var viewModel: HomeViewModel
    @State private var showsSettings = false
    @State private var showsGarage = false
    @Environment(\.modelContext) private var modelContext
    private let locationManager: LocationManager

    var onStartTrip: () -> Void
    var onSelectTrip: (Trip) -> Void

    init(
        locationManager: LocationManager,
        onStartTrip: @escaping () -> Void,
        onSelectTrip: @escaping (Trip) -> Void
    ) {
        self.locationManager = locationManager
        _viewModel = State(initialValue: HomeViewModel(locationManager: locationManager))
        self.onStartTrip = onStartTrip
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
                            .frame(height: 100)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }

            VStack {
                Spacer()
                Button {
                    viewModel.startTripTapped(onAuthorized: onStartTrip)
                } label: {
                    Label("Sürüşe Başla", systemImage: "location.fill")
                }
                .buttonStyle(.glass(.accent))
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(locationManager: locationManager)
        }
        .sheet(isPresented: $showsGarage) {
            GarageView()
        }
        #if DEBUG
        .task {
            // Test-only hook: launching with -uiTestAutoGarage opens the
            // Garage sheet automatically so it can be verified without taps.
            guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoGarage") else { return }
            try? await Task.sleep(for: .seconds(1))
            showsGarage = true
        }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoSettings") else { return }
            try? await Task.sleep(for: .seconds(1))
            showsSettings = true
        }
        #endif
        .alert("Konum İzni Gerekli", isPresented: $viewModel.showsPermissionAlert) {
            Button("Ayarları Aç") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Sürüşünü kaydedebilmek için Ayarlar'dan konum iznini etkinleştir.")
        }
    }

    private var header: some View {
        HStack {
            Text("Trackline")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            Button {
                showsGarage = true
            } label: {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 17))
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
