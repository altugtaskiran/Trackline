//
//  FeatureFlags.swift
//  fastAndCar
//
//  Toggles for features whose code is complete but shouldn't be reachable
//  right now — e.g. CloudKit-backed features that need a paid Apple
//  Developer Program membership (personal/free teams can't get iCloud or
//  Push Notifications entitlements). Paid membership confirmed active
//  2026-09-19 — a freshly issued (not cached) provisioning profile carries
//  the iCloud entitlement with no rejection from Apple's provisioning API,
//  after an earlier same-day check had explicitly rejected it as a
//  Personal Team (propagation lag between App Store Connect and the
//  Developer Portal, not a real problem).
//

enum FeatureFlags {
    /// User-defined segments + the Global Leaderboard tab (Segment,
    /// SegmentEffort — CloudKitSegmentService).
    static let globalLeaderboardEnabled = true
    /// Crew creation/invites/drive comparison (Crew, CrewMembership,
    /// CrewDriveSummary — CloudKitCrewService + CKShare). Same gate.
    static let crewEnabled = true
}
