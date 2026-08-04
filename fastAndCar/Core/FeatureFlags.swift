//
//  FeatureFlags.swift
//  fastAndCar
//
//  Toggles for features whose code is complete but shouldn't be reachable
//  right now — e.g. CloudKit-backed features that need a paid Apple
//  Developer Program membership (personal/free teams can't get iCloud or
//  Push Notifications entitlements). Flip back to true once that's sorted.
//

enum FeatureFlags {
    static let leaderboardEnabled = false
}
