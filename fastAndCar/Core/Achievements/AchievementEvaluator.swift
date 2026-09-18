//
//  AchievementEvaluator.swift
//  fastAndCar
//
//  Pure function over the trip history, same "no persistence/UI concerns,
//  easy to test in isolation" pattern as TripStatsCalculator — recomputed
//  from scratch each time rather than tracked incrementally, so there's
//  never a stale/out-of-sync unlocked set to worry about.
//

import Foundation

enum AchievementEvaluator {
    private static let distanceThresholds: [(id: String, meters: Double)] = [
        ("distance_100", 100_000),
        ("distance_500", 500_000),
        ("distance_1000", 1_000_000),
    ]
    private static let centuryDriveMeters = 50_000.0
    private static let smoothOperatorMinMeters = 1_000.0
    private static let nightOwlStartHour = 0
    private static let nightOwlEndHour = 5
    private static let streakLengthDays = 7

    static func unlockedIds(for trips: [Trip]) -> Set<String> {
        guard !trips.isEmpty else { return [] }
        var unlocked: Set<String> = ["first_drive"]

        let totalDistance = trips.reduce(0.0) { $0 + $1.distanceMeters }
        for threshold in distanceThresholds where totalDistance >= threshold.meters {
            unlocked.insert(threshold.id)
        }

        if trips.contains(where: { isNightDrive($0.startTime) }) {
            unlocked.insert("night_owl")
        }

        if trips.contains(where: { $0.distanceMeters >= smoothOperatorMinMeters && $0.harshBrakeCount == 0 }) {
            unlocked.insert("smooth_operator")
        }

        if trips.contains(where: { $0.distanceMeters >= centuryDriveMeters }) {
            unlocked.insert("century_drive")
        }

        if hasConsecutiveDayStreak(trips, length: streakLengthDays) {
            unlocked.insert("week_streak")
        }

        return unlocked
    }

    private static func isNightDrive(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= nightOwlStartHour && hour < nightOwlEndHour
    }

    private static func hasConsecutiveDayStreak(_ trips: [Trip], length: Int) -> Bool {
        let calendar = Calendar.current
        let days = Set(trips.map { calendar.startOfDay(for: $0.startTime) }).sorted()
        guard days.count >= length else { return false }

        var streak = 1
        for index in 1..<days.count {
            let dayGap = calendar.dateComponents([.day], from: days[index - 1], to: days[index]).day ?? 0
            streak = dayGap == 1 ? streak + 1 : 1
            if streak >= length { return true }
        }
        return false
    }
}
