//
//  CreateSegmentFlowView.swift
//  fastAndCar
//
//  "Bu rotadan segment oluştur" — picks a start/end sub-range of the
//  current trip's own recorded route (two sliders over sample index, not a
//  freehand map draw) and publishes it as a named Segment other drivers'
//  trips can later match against.
//

import SwiftUI

struct CreateSegmentFlowView: View {
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var nicknameStore = NicknameStore()
    @State private var myCreatedSegmentsStore = MyCreatedSegmentsStore()
    @State private var localRoutesStore = LocalRoutesStore()
    @State private var startIndex: Double = 0
    @State private var endIndex: Double
    @State private var name = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showsNicknamePrompt = false
    // Off by default — publishing to the public Global Leaderboard used to
    // happen automatically on every locally created route, which read as
    // surprising/unwanted. Now it's the driver's own explicit choice.
    @State private var publishesGlobally = false
    @FocusState private var isNameFieldFocused: Bool

    // `trip.samples` decodes the whole recorded route from its stored JSON
    // blob on every access — fine for a one-off read, but this view's two
    // sliders trigger dozens of body re-evaluations per second while
    // dragging, and re-decoding a potentially thousand-plus-point array
    // that often is exactly what was freezing the sheet on device. Decoded
    // once here, into a plain array every other computed property below
    // just slices/iterates in memory.
    private let samples: [LocationSample]

    init(trip: Trip) {
        self.trip = trip
        let decodedSamples = trip.samples
        samples = decodedSamples
        _endIndex = State(initialValue: Double(max(decodedSamples.count - 1, 1)))
    }

    private var clampedStart: Int {
        min(max(Int(startIndex), 0), max(samples.count - 2, 0))
    }

    private var clampedEnd: Int {
        min(max(Int(endIndex), clampedStart + 1), max(samples.count - 1, 1))
    }

    private var previewSamples: [LocationSample] {
        guard samples.indices.contains(clampedStart), samples.indices.contains(clampedEnd), clampedStart < clampedEnd else { return [] }
        return Array(samples[clampedStart...clampedEnd])
    }

    private var previewDistanceMeters: Double {
        guard previewSamples.count > 1 else { return 0 }
        var total = 0.0
        for index in 1..<previewSamples.count {
            total += GeoMath.distanceMeters(from: previewSamples[index - 1].coordinate, to: previewSamples[index].coordinate)
        }
        return total
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()
                    .onTapGesture { isNameFieldFocused = false }

                ScrollView {
                    VStack(spacing: 20) {
                        RouteCanvas(samples: previewSamples, lineWidth: 3, showsEndpoints: true, padding: 20)
                            .frame(height: 220)
                            .glassCard(cornerRadius: 22, padding: 0)

                        GlassCard {
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Başlangıç")
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.textSecondary)
                                    Slider(value: $startIndex, in: 0...Double(max(samples.count - 2, 1)))
                                        .tint(AppColor.routeStart)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Bitiş")
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.textSecondary)
                                    Slider(value: $endIndex, in: Double(clampedStart + 1)...Double(max(samples.count - 1, 1)))
                                        .tint(AppColor.routeEnd)
                                }
                                Text(String(format: "%.1f km", previewDistanceMeters / 1000))
                                    .font(AppFont.statValue(16))
                                    .foregroundStyle(AppColor.textPrimary)
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Parkur Adı")
                                    .font(AppFont.headline)
                                    .foregroundStyle(AppColor.textPrimary)
                                TextField("örn. Sahil Yolu Düz", text: $name)
                                    .font(AppFont.body)
                                    .foregroundStyle(AppColor.textPrimary)
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColor.surfaceElevated))
                                    .focused($isNameFieldFocused)
                            }
                        }

                        GlassCard {
                            Toggle("Herkese Açık Liderlik Tablosuna Ekle", isOn: $publishesGlobally)
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                                .tint(AppColor.accent)
                        }

                        Button {
                            submit()
                        } label: {
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("Parkur Oluştur")
                            }
                        }
                        .buttonStyle(.glass(.accent))
                        .disabled(trimmedName.isEmpty || isSubmitting || previewSamples.count < 2)
                    }
                    .padding(20)
                    // contentShape makes the gaps between cards tappable
                    // too, not just the cards themselves — tapping anywhere
                    // on this screen dismisses the keyboard, not only the
                    // "Parkur Oluştur" button at the bottom, which meant
                    // scrolling all the way down was the only way out.
                    .contentShape(Rectangle())
                    .onTapGesture { isNameFieldFocused = false }
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle("Parkur Oluştur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsNicknamePrompt) {
            NicknamePromptView(nicknameStore: nicknameStore) {
                submit()
            }
        }
        .alert(
            "Bir Sorun Oluştu",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("Tamam") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Always saved locally first — that's what makes "kaydet, sonra aynı
    /// rotada tekrar sür" work today, with no dependency on CloudKit being
    /// active. Publishing to the public Global Leaderboard is attempted
    /// best-effort on top of that, never a requirement for the local route
    /// to exist and be drivable again.
    private func submit() {
        guard nicknameStore.hasNickname else {
            showsNicknamePrompt = true
            return
        }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            guard let segment = Segment.fromTripRange(
                samples: samples,
                startIndex: clampedStart,
                endIndex: clampedEnd,
                name: trimmedName,
                creatorId: "local",
                creatorNickname: nicknameStore.nickname
            ) else {
                errorMessage = "Bu aralıktan bir parkur oluşturulamadı."
                return
            }

            localRoutesStore.add(segment)

            // Only touch the public Global Leaderboard (and its local
            // "Oluşturduklarım" cache) when the driver explicitly opted in
            // above — otherwise this route stays exactly what it looked
            // like it'd be: a private local route, nothing sent anywhere.
            if publishesGlobally {
                myCreatedSegmentsStore.record(id: segment.id, name: segment.name)
                if let userId = try? await CloudKitSegmentService.currentUserId() {
                    var publicSegment = segment
                    publicSegment.creatorId = userId
                    try? await CloudKitSegmentService.createSegment(publicSegment)
                }
            }

            dismiss()
        }
    }
}
