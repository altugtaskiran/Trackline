//
//  ShareCardView.swift
//  fastAndCar
//
//  Preview sheet for the rendered share card, backed by the native activity
//  sheet — one "Paylaş" button reaches every platform.
//

import SwiftData
import SwiftUI

struct ShareCardView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Car.createdAt, order: .reverse) private var cars: [Car]
    let trip: Trip

    @State private var renderedImage: UIImage?
    @State private var showsActivitySheet = false
    @State private var selectedCar: Car?
    @State private var didPickCar = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                VStack(spacing: 16) {
                    // GeometryReader measures the *actual* leftover space
                    // (after the picker/button below claim their natural
                    // height) and imageFitSize computes the exact width and
                    // height that fits the card's true 360:640 ratio inside
                    // it — this replaces relying on scaledToFit's automatic
                    // negotiation, which on some screen sizes still left the
                    // image height-bound and narrower than the screen
                    // (black bars on the sides).
                    GeometryReader { geo in
                        Group {
                            if let renderedImage {
                                let fitSize = imageFitSize(for: renderedImage.size, in: geo.size)
                                Image(uiImage: renderedImage)
                                    .resizable()
                                    .frame(width: fitSize.width, height: fitSize.height)
                                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                                            .strokeBorder(AppColor.glassBorder, lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
                            } else {
                                ProgressView().tint(AppColor.accent)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }

                    if !cars.isEmpty {
                        carPicker
                    }

                    Button("Paylaş") {
                        showsActivitySheet = true
                    }
                    .buttonStyle(.glass(.accent))
                    .disabled(renderedImage == nil)
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
            .navigationTitle("Paylaş")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(AppColor.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if !didPickCar {
                selectedCar = cars.first
                didPickCar = true
            }
            renderedImage = ShareCardRenderer.render(trip: trip, carPhotoData: selectedCar?.photoData)
        }
        .onChange(of: selectedCar) { _, newValue in
            renderedImage = ShareCardRenderer.render(trip: trip, carPhotoData: newValue?.photoData)
        }
        .sheet(isPresented: $showsActivitySheet) {
            if let renderedImage {
                ActivityShareSheet(items: [renderedImage], image: renderedImage)
            }
        }
    }

    private var carPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                carChip(title: "Yok", isSelected: selectedCar == nil) {
                    selectedCar = nil
                }
                ForEach(cars) { car in
                    carChip(title: car.displayName, isSelected: selectedCar?.id == car.id) {
                        selectedCar = car
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// Exact aspect-fit math using the rendered image's *real* size (not an
    /// assumed constant) — whichever axis of `containerSize` is more
    /// constraining wins, the other axis is derived from it, so the result
    /// always fills the full width unless the container is genuinely too
    /// short for that width.
    private func imageFitSize(for imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard containerSize.width > 0, containerSize.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let imageAspect = imageSize.width / imageSize.height
        let widthIfHeightBound = containerSize.height * imageAspect
        if widthIfHeightBound <= containerSize.width {
            return CGSize(width: widthIfHeightBound, height: containerSize.height)
        } else {
            return CGSize(width: containerSize.width, height: containerSize.width / imageAspect)
        }
    }

    private func carChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(isSelected ? AppColor.background : AppColor.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(isSelected ? AppColor.accent : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: [InstagramStoryActivity(image: image)])
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
