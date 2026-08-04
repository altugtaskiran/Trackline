//
//  AddCarView.swift
//  fastAndCar
//
//  Simple add-car form: photo picker + specs. No editing yet — delete and
//  re-add covers corrections for now.
//

import PhotosUI
import SwiftData
import SwiftUI

struct AddCarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var make = ""
    @State private var model = ""
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var horsepower = 200
    @State private var fuelType: FuelType = .gasoline
    @State private var mileageKm = 0
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        photoPicker

                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                labeledField("Marka", text: $make)
                                labeledField("Model", text: $model)
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 12) {
                                    numericField("Yıl", value: $year)
                                    numericField("Beygir Gücü", value: $horsepower)
                                }
                                numericField("Kilometre", value: $mileageKm, groupsThousands: true)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Yakıt")
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.textSecondary)
                                    Picker("Yakıt", selection: $fuelType) {
                                        ForEach(FuelType.allCases) { type in
                                            Text(type.label).tag(type)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }
                            .foregroundStyle(AppColor.textPrimary)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Araç Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .foregroundStyle(AppColor.accent)
                        .disabled(make.isEmpty || model.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: photoItem) {
            guard let photoItem, let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
            photoData = data
        }
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            Group {
                if let photoData, let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        AppColor.surfaceElevated
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill").font(.system(size: 28))
                            Text("Araç Fotoğrafı Ekle").font(AppFont.caption)
                        }
                        .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipped()
        }
        .buttonStyle(.plain)
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            TextField(title, text: text)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppColor.surfaceElevated))
        }
    }

    private func numericField(_ title: String, value: Binding<Int>, groupsThousands: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            TextField(title, value: value, format: .number.grouping(groupsThousands ? .automatic : .never))
                .keyboardType(.numberPad)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppColor.surfaceElevated))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        let car = Car(
            make: make,
            model: model,
            year: year,
            horsepower: horsepower,
            fuelType: fuelType,
            mileageKm: mileageKm,
            photoData: photoData
        )
        modelContext.insert(car)
        dismiss()
    }
}
