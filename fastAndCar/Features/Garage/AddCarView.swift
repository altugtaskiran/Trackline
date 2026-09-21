//
//  AddCarView.swift
//  fastAndCar
//
//  Add-car form; also doubles as the edit form — pass an existingCar and
//  every field preloads from it, and Save updates that same SwiftData
//  object in place instead of inserting a new one.
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

    let existingCar: Car?

    @State private var make: String
    @State private var model: String
    @State private var year: Int
    @State private var horsepower: Int
    @State private var fuelType: FuelType
    @State private var mileageKm: Int
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var pickedImageForCrop: IdentifiableImage?
    @State private var showsBrandPicker = false
    @State private var showsModelPicker = false

    init(existingCar: Car? = nil) {
        self.existingCar = existingCar
        _make = State(initialValue: existingCar?.make ?? "")
        _model = State(initialValue: existingCar?.model ?? "")
        _year = State(initialValue: existingCar?.year ?? Calendar.current.component(.year, from: Date()))
        _horsepower = State(initialValue: existingCar?.horsepower ?? 200)
        _fuelType = State(initialValue: existingCar?.fuelType ?? .gasoline)
        _mileageKm = State(initialValue: existingCar?.mileageKm ?? 0)
        _photoData = State(initialValue: existingCar?.photoData)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        photoPicker

                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                pickerField("Marka", value: make, placeholder: "Marka") { showsBrandPicker = true }
                                pickerField("Model", value: model, placeholder: "Model") { showsModelPicker = true }
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 12) {
                                    yearField
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
            .navigationTitle(existingCar == nil ? "Araç Ekle" : "Aracı Düzenle")
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
        .sheet(isPresented: $showsBrandPicker) {
            CarPickerSheet(title: "Marka", items: CarCatalog.brands) { picked in
                if picked != make { model = "" }
                make = picked
            }
        }
        .sheet(isPresented: $showsModelPicker) {
            CarPickerSheet(title: "Model", items: CarCatalog.models(for: make)) { picked in
                model = picked
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
                        LinearGradient(
                            colors: [AppColor.surfaceElevated, AppColor.surfaceElevated.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(AppColor.accent.opacity(0.15))
                                    .frame(width: 56, height: 56)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(AppColor.accent)
                            }
                            Text("Araç Fotoğrafı Ekle")
                                .font(AppFont.caption.weight(.semibold))
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                if photoData == nil {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                }
            }
            .clipped()
        }
        .buttonStyle(.plain)
    }

    private func pickerField(_ title: LocalizedStringKey, value: String, placeholder: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Button(action: action) {
                HStack {
                    if value.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(AppColor.textTertiary)
                    } else {
                        Text(value)
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }
                .font(AppFont.body)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppColor.surfaceElevated))
            }
            .buttonStyle(.plain)
        }
    }

    private var yearField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Yıl")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            // A plain .pickerStyle(.menu) Picker hugs its label's content
            // width instead of respecting .frame(maxWidth: .infinity) the
            // way TextField does, which is why this used to render
            // narrower than Beygir Gücü next to it — a Menu with the same
            // HStack+padding+background structure as numericField's
            // TextField forces identical, symmetric sizing instead.
            Menu {
                ForEach((1970...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { yearOption in
                    Button(String(yearOption)) { year = yearOption }
                }
            } label: {
                HStack {
                    Text(String(year))
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppColor.surfaceElevated))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        if let existingCar {
            existingCar.make = make
            existingCar.model = model
            existingCar.year = year
            existingCar.horsepower = horsepower
            existingCar.fuelType = fuelType
            existingCar.mileageKm = mileageKm
            existingCar.photoData = photoData
        } else {
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
        }
        dismiss()
    }
}
