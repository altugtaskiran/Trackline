//
//  NotifiedAchievementsStore.swift
//  fastAndCar
//
//  Tracks which unlocked achievements have already fired a local
//  notification, so re-evaluating on every trip save (cheap, since it's
//  just scanning denormalized Trip fields) doesn't re-notify for badges
//  earned trips ago. Same UserDefaults-backed pattern as NicknameStore.
//

import Foundation

struct NotifiedAchievementsStore {
    private static let key = "notifiedAchievementIds"

    private(set) var notifiedIds: Set<String>

    init() {
        notifiedIds = Self.load()
    }

    /// Returns only the ids from `unlockedIds` that hadn't already been
    /// notified, and records all of `unlockedIds` as notified — call once
    /// per evaluation, right before posting notifications for the result.
    mutating func newlyUnlocked(from unlockedIds: Set<String>) -> Set<String> {
        let newIds = unlockedIds.subtracting(notifiedIds)
        guard !newIds.isEmpty else { return [] }
        notifiedIds.formUnion(unlockedIds)
        save()
        return newIds
    }

    private static func load() -> Set<String> {
        guard let array = UserDefaults.standard.array(forKey: key) as? [String] else { return [] }
        return Set(array)
    }

    private func save() {
        UserDefaults.standard.set(Array(notifiedIds), forKey: Self.key)
    }
}
