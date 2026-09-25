//
//  GlobalStatsLeaderboardView.swift
//  fastAndCar
//
//  Cross-user ranking (all drivers, not just one Segment's racers) — two
//  metrics: total distance ever driven, and highest-ever recorded top
//  speed. Reads CloudKitProfileService.fetchGlobalStatLeaderboard(metric:),
//  a sorted CKQuery over the same userProfile records syncStats already
//  writes to on every trip end.
//

import SwiftUI

struct GlobalStatsLeaderboardView: View {
    @State private var metric: CloudKitProfileService.GlobalStatMetric = .totalDistance
    @State private var entries: [CloudKitProfileService.GlobalStatEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedUser: (userId: String, nickname: String, tag: Int)?
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            VStack(spacing: 16) {
                Picker("Metrik", selection: $metric) {
                    Text("Toplam Mesafe").tag(CloudKitProfileService.GlobalStatMetric.totalDistance)
                    Text("En Yüksek Hız").tag(CloudKitProfileService.GlobalStatMetric.topSpeed)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 12)

                if isLoading {
                    Spacer()
                    ProgressView().tint(AppColor.accent)
                    Spacer()
                } else if entries.isEmpty {
                    Spacer()
                    Text("Henüz kimse bu kategoride sıralanmadı.")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                Button {
                                    selectedUser = (entry.userId, entry.nickname, entry.tag)
                                } label: {
                                    row(rank: index + 1, entry: entry)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
        .navigationTitle("Global İstatistik")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: metric) { await load() }
        .sheet(item: Binding(
            get: { selectedUser.map { IdentifiableUser(userId: $0.userId, nickname: $0.nickname, tag: $0.tag) } },
            set: { if $0 == nil { selectedUser = nil } }
        )) { user in
            PublicProfileView(userId: user.userId, nickname: user.nickname, tag: user.tag)
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

    /// Gold/silver/bronze for the top 3, nil (plain) from #4 on — mirrors
    /// SegmentEffortRow's per-segment leaderboard styling so the two
    /// leaderboards read as the same visual language.
    private func rankColor(_ rank: Int) -> Color? {
        switch rank {
        case 1: Color(hex: 0xFFD60A)
        case 2: Color(hex: 0xC0C0C8)
        case 3: Color(hex: 0xCD7F32)
        default: nil
        }
    }

    private func row(rank: Int, entry: CloudKitProfileService.GlobalStatEntry) -> some View {
        let rankColor = rankColor(rank)
        return HStack(spacing: 14) {
            Text("#\(rank)")
                .font(AppFont.statValue(16))
                .foregroundStyle(rankColor ?? AppColor.textSecondary)
                .frame(width: 32, alignment: .leading)

            ZStack {
                if rank == 1 {
                    // Same soft warm halo as SegmentEffortRow's #1 row.
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: 0xFF9F0A).opacity(0.6), .clear],
                                center: .center, startRadius: 2, endRadius: 26
                            )
                        )
                        .frame(width: 52, height: 52)
                        .blur(radius: 5)
                }
                AvatarView(image: nil, initial: entry.nickname.first, size: 36)
                    .overlay {
                        if let rankColor {
                            Circle().strokeBorder(rankColor, lineWidth: rank == 1 ? 2.5 : 2)
                        }
                    }
            }

            // Text(String), not the LocalizedStringKey-interpolation form
            // — the latter formats interpolated Ints with locale grouping
            // (e.g. "9.301" instead of "9301" under tr_TR).
            Text("\(entry.nickname)#\(entry.tag)" as String)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)

            Spacer()

            Text(formattedValue(entry.value))
                .font(AppFont.statValue(17))
                .foregroundStyle(AppColor.accent)
        }
        .background {
            if rank == 1 {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: 0xFF9F0A).opacity(0.35))
                    .blur(radius: 18)
                    .padding(-6)
            }
        }
        .glassCard(cornerRadius: 18, padding: 14)
        .overlay {
            if rank == 1 {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color(hex: 0xFFD60A), Color(hex: 0xFF9F0A)], startPoint: .leading, endPoint: .trailing),
                        lineWidth: 1.5
                    )
            }
        }
    }

    private func formattedValue(_ value: Double) -> String {
        switch metric {
        case .totalDistance: return distanceUnit.distanceString(meters: value)
        case .topSpeed: return distanceUnit.speedString(kph: value)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await CloudKitProfileService.fetchGlobalStatLeaderboard(metric: metric)
        } catch SegmentServiceError.featureNotAvailable {
            entries = []
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
    }
}

private struct IdentifiableUser: Identifiable {
    var id: String { userId }
    let userId: String
    let nickname: String
    let tag: Int
}
