//
//  PhotoCropView.swift
//  fastAndCar
//
//  Pinch-to-zoom + drag-to-reposition before a car photo gets saved — cars
//  are rarely framed exactly how the Share card's full-bleed 9:16 hero
//  needs them, so this lets the user pick which part of their photo that
//  actually is instead of always getting whatever a plain scaledToFill
//  center-crop lands on.
//

import SwiftUI

struct PhotoCropView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    var onCrop: (Data) -> Void

    // Matches ShareCardRenderer's fixed 360×640 (9:16) hero canvas — that
    // full-bleed use is the one where "car's too small/far away" actually
    // bites, so the crop tool composes for that aspect ratio specifically.
    private let cropSize = CGSize(width: 280, height: 280 * 640 / 360)
    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 4

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                VStack(spacing: 20) {
                    Spacer()

                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: cropSize.width, height: cropSize.height)
                            .scaleEffect(scale)
                            .offset(offset)
                    }
                    .frame(width: cropSize.width, height: cropSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = min(max(lastScale * value, minScale), maxScale)
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    offset = clampedOffset(offset)
                                    lastOffset = offset
                                },
                            DragGesture()
                                .onChanged { value in
                                    let proposed = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                    offset = clampedOffset(proposed)
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                    )

                    Text("Yakınlaştırmak için sıkıştır, konumlandırmak için sürükle")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()

                    Button("Kullan") {
                        crop()
                    }
                    .buttonStyle(.glass(.accent))
                }
                .padding(20)
            }
            .navigationTitle("Fotoğrafı Ayarla")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Approximate clamp (doesn't account for the source image's own
    /// aspect ratio vs the crop frame's) — good enough to stop the photo
    /// being dragged wildly off-frame without needing to precompute
    /// scaledToFill's true fitted size.
    private func clampedOffset(_ proposed: CGSize) -> CGSize {
        let maxX = cropSize.width * (scale - 1) / 2
        let maxY = cropSize.height * (scale - 1) / 2
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    @MainActor
    private func crop() {
        let content = Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: cropSize.width, height: cropSize.height)
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: cropSize.width, height: cropSize.height)
            .clipped()

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3.0
        if let uiImage = renderer.uiImage, let data = uiImage.jpegData(compressionQuality: 0.9) {
            onCrop(data)
        }
        dismiss()
    }
}
