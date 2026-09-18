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

struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

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
    @State private var pickedImageForCrop: IdentifiableImage?

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
            guard let photoItem,
                  let data = try? await photoItem.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else { return }
            // PhotosPicker's own presentation is still mid-dismissal right
            // as this fires — presenting another sheet in the same beat
            // raced it and lost (a blank/gray sheet with none of its
            // content, not even the Kullan button), so this gives that
            // transition a moment to actually finish first.
            try? await Task.sleep(for: .milliseconds(250))
            pickedImageForCrop = IdentifiableImage(image: uiImage)
        }
        // .sheet(item:) instead of a separate Bool + optional-image pair —
        // this guarantees the sheet's content closure only ever runs with
        // a real, already-non-nil image, so there's no window where it
        // could present before rawPickedImage was actually set.
        .sheet(item: $pickedImageForCrop) { wrapped in
            PhotoCropView(image: wrapped.image) { croppedData in
                photoData = croppedData
            }
        }
        #if DEBUG
        .task {
            // Test-only hook: launching with -uiTestAutoCropTest opens the
            // crop sheet with a synthetic generated image, bypassing
            // PhotosPicker entirely — PhotosPicker needs a real photo
            // library selection that can't be scripted, so this is how
            // PhotoCropView's own rendering gets verified in isolation.
            guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoCropTest") else { return }
            try? await Task.sleep(for: .seconds(1))
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600))
            let testImage = renderer.image { context in
                UIColor.systemBlue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
                UIColor.white.setFill()
                context.fill(CGRect(x: 350, y: 250, width: 100, height: 100))
            }
            pickedImageForCrop = IdentifiableImage(image: testImage)
        }
        #endif
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

    private func labeledField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
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

    private func numericField(_ title: LocalizedStringKey, value: Binding<Int>, groupsThousands: Bool = false) -> some View {
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
