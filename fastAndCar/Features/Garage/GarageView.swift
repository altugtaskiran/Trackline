//
//  GarageView.swift
//  fastAndCar
//
//  The user's cars: photo + specs. Reached from a small icon on Home,
//  same pattern as Settings.
//

import SwiftData
import SwiftUI

struct GarageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Car.createdAt, order: .reverse) private var cars: [Car]
    @State private var showsAddCar = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 14) {
                        if cars.isEmpty {
                            emptyState
                        } else {
                            ForEach(cars) { car in
                                CarCard(car: car) {
                                    modelContext.delete(car)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Garaj")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(AppColor.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsAddCar = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .foregroundStyle(AppColor.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsAddCar) {
            AddCarView()
        }
        #if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoAddCar") else { return }
            try? await Task.sleep(for: .seconds(1))
            showsAddCar = true
        }
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppColor.textTertiary)
            Text("Garajın boş")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Aracını ekle, paylaşım kartlarında ve gelecekte istatistiklerinde görünsün.")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Araç Ekle") {
                showsAddCar = true
            }
            .buttonStyle(.glass(.accent))
            .padding(.top, 8)
        }
        .padding(.top, 100)
    }
}
