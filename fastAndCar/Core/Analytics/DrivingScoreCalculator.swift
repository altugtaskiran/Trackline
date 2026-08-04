//
//  DrivingScoreCalculator.swift
//  fastAndCar
//
//  Deterministic, on-device driving-score heuristic (not an ML/LLM call):
//  penalizes harsh braking/acceleration, inconsistent speed, and excessive
//  stopped time, then renders a short human-readable explanation.
//

import Foundation

struct DrivingScore: Codable, Equatable {
    var value: Int
    var insights: [String]
}

enum DrivingScoreCalculator {
    private static let gravity = 9.80665
    private static let harshAccelThresholdG = 0.35
    /// Same GPS-glitch guard as TripStatsCalculator — an implausible position
    /// jump must not read as a harsh brake/accel event.
    private static let maxPlausibleSpeedMps = 83.0

    static func calculate(samples: [LocationSample], stats: TripStats) -> DrivingScore {
        guard samples.count > 1 else {
            return DrivingScore(value: 100, insights: ["Skor için yeterli veri yok"])
        }

        var harshBrakeCount = 0
        var harshAccelCount = 0
        var movingSpeeds: [Double] = []

        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let sample = samples[index]
            let dt = sample.timestamp.timeIntervalSince(previous.timestamp)
            guard dt > 0 else { continue }
            guard GeoMath.distanceMeters(from: previous.coordinate, to: sample.coordinate) / dt <= maxPlausibleSpeedMps else { continue }

            let accelG = ((sample.speedMps - previous.speedMps) / dt) / gravity
            if accelG <= -harshAccelThresholdG { harshBrakeCount += 1 }
            if accelG >= harshAccelThresholdG { harshAccelCount += 1 }
            if sample.speedMps > 1 { movingSpeeds.append(sample.speedKph) }
        }

        let meanSpeed = movingSpeeds.isEmpty ? 0 : movingSpeeds.reduce(0, +) / Double(movingSpeeds.count)
        let variance = movingSpeeds.isEmpty ? 0 : movingSpeeds.reduce(0) { $0 + pow($1 - meanSpeed, 2) } / Double(movingSpeeds.count)
        let speedConsistency = meanSpeed > 0 ? sqrt(variance) / meanSpeed : 0
        let stoppedRatio = stats.driveTime > 0 ? stats.stoppedTime / stats.driveTime : 0

        var score = 100.0
        score -= Double(harshBrakeCount) * 4
        score -= Double(harshAccelCount) * 3
        score -= min(speedConsistency * 40, 25)
        score -= min(stoppedRatio * 30, 15)
        score = min(max(score, 0), 100)

        let insights = [
            harshBrakeCount <= 1 ? "Ani fren az" : "\(harshBrakeCount) ani fren tespit edildi",
            speedConsistency < 0.35 ? "Ortalama hız dengeli" : "Hız değişkenliği yüksek",
            harshAccelCount <= 1 ? "Kalkışlar ve virajlar kontrollü" : "Ani hızlanmalar fazla",
            stoppedRatio < 0.15 ? "Akıcı sürüş, yakıt verimliliği yüksek" : "Sık duruşlar yakıt verimliliğini düşürüyor",
        ]

        return DrivingScore(value: Int(score.rounded()), insights: insights)
    }
}
