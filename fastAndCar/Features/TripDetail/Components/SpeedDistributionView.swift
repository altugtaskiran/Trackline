//
//  SpeedDistributionView.swift
//  fastAndCar
//
//  A colored horizontal bar + legend showing what share of this drive was
//  spent at low/medium/high/top speed — buckets are relative to this trip's
//  own top speed (quartiles), not fixed km/h thresholds, so it reads
//  sensibly whether the drive was a city errand or a track day.
//

import SwiftUI

struct SpeedDistributionView: View {
    let samples: [LocationSample]
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.systemDefault.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .systemDefault }

    private struct Bucket: Identifiable {
        let id = UUID()
        let lower: Double
        let upper: Double
        let color: Color
        let count: Int
    }

    private static let colors = [Color(hex: 0x32ADE6), Color(hex: 0x34C759), Color(hex: 0xFF9500), Color(hex: 0xFF3B30)]

    private var buckets: [Bucket] {
        let speeds = samples.map(\.speedKph).filter { $0 > 1 }
        guard let maxSpeed = speeds.max(), maxSpeed > 0 else { return [] }
        let step = maxSpeed / 4
        return (0..<4).map { index in
            let lower = step * Double(index)
            let upper = index == 3 ? maxSpeed : step * Double(index + 1)
            let count = speeds.filter { $0 >= lower && (index == 3 ? $0 <= upper : $0 < upper) }.count
            return Bucket(lower: lower, upper: upper, color: Self.colors[index], count: count)
        }
    }

    private var total: Int { buckets.reduce(0) { $0 + $1.count } }

    var body: some View {
        if total > 0 {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Hız Dağılımı")
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .textCase(.uppercase)
                    Spacer()
                    Text(distanceUnit.speedSymbol)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }

                HStack(spacing: 2) {
                    ForEach(buckets) { bucket in
                        if bucket.count > 0 {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(bucket.color)
                                .frame(width: max(4, CGFloat(bucket.count) / CGFloat(total) * 300))
                        }
                    }
                }
                .frame(height: 8)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .top, spacing: 0) {
                    ForEach(buckets) { bucket in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Circle().fill(bucket.color).frame(width: 7, height: 7)
                                Text("\(distanceUnit.speedValue(kph: bucket.lower))–\(distanceUnit.speedValue(kph: bucket.upper))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            Text("\(Int((Double(bucket.count) / Double(total) * 100).rounded()))%")
                                .font(AppFont.statValue(16))
                                .foregroundStyle(AppColor.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .glassCard(cornerRadius: 18, padding: 16)
        }
    }
}
