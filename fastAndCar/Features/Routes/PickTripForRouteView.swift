//
//  PickTripForRouteView.swift
//  fastAndCar
//
//  Step one of "Sürüşten Rota Oluştur" — pick which saved drive to build a
//  route from. Step two (picking the start/end sub-range within that
//  drive) is the existing CreateSegmentFlowView, pushed once a trip's
//  chosen here.
//

import SwiftData
import SwiftUI

struct PickTripForRouteView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @State private var selectedTrip: Trip?

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                if trips.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(trips) { trip in
                                Button {
                                    selectedTrip = trip
                                } label: {
                                    TripRowCard(trip: trip)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Bir Sürüş Seç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .navigationDestination(item: $selectedTrip) { trip in
                CreateSegmentFlowView(trip: trip)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "car.side")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.textTertiary)
            Text("Henüz kaydedilmiş bir sürüşün yok")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Önce bir sürüş kaydet, sonra ondan bir rota oluşturabilirsin.")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
}
