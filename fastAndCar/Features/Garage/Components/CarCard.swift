//
//  CarCard.swift
//  fastAndCar
//

import SwiftUI

struct CarCard: View {
    let car: Car
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            photo
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 10) {
                Text(car.displayName)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                HStack(spacing: 8) {
                    specChip(icon: "bolt.fill", text: "\(car.horsepower) HP")
                    specChip(icon: "calendar", text: "\(car.year)")
                    specChip(icon: "fuelpump.fill", text: car.fuelType.label)
                }
                specChip(icon: "gauge.with.needle", text: "\(car.mileageKm.formatted(.number.grouping(.automatic))) km")
            }
            .padding(16)
        }
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(AppColor.glassBorder, lineWidth: 1))
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Sil", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var photo: some View {
        if let data = car.photoData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(AppColor.surfaceElevated)
                .overlay(
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(AppColor.textTertiary)
                )
        }
    }

    private func specChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(AppFont.caption)
        }
        .foregroundStyle(AppColor.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(AppColor.surfaceElevated))
    }
}
