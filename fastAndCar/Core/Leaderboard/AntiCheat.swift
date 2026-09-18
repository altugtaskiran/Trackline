//
//  AntiCheat.swift
//  fastAndCar
//
//  Cheap, local guards against obviously-bogus or spammy CloudKit writes.
//  Not a substitute for server-side validation (the public database has
//  none here), but enough to keep a single confused or malicious client
//  from trashing a segment's leaderboard.
//

import Foundation

enum AntiCheat {
    /// Rejects speeds no road-legal car reaches — a GPS jump (tunnel exit,
    /// teleporting between cell-tower fixes) is a far more likely cause
    /// than a genuine 300+ km/h pass.
    static let maxPlausibleSpeedKph = 300.0

    static func isPlausible(topSpeedKph: Double, averageSpeedKph: Double) -> Bool {
        guard topSpeedKph <= maxPlausibleSpeedKph, averageSpeedKph <= maxPlausibleSpeedKph else { return false }
        guard averageSpeedKph <= topSpeedKph * 1.05 else { return false }
        return true
    }

    /// Local per-user write throttle for segment-effort submissions — keeps
    /// a scripted client from flooding a segment's leaderboard with
    /// fabricated efforts. Real drives naturally submit at most a handful
    /// of efforts per session, so this only ever bites automated abuse.
    private static let minIntervalBetweenSubmissions: TimeInterval = 5
    private static let key = "antiCheatLastSubmission"

    static func canSubmitNow() -> Bool {
        guard let last = UserDefaults.standard.object(forKey: key) as? Date else { return true }
        return Date().timeIntervalSince(last) >= minIntervalBetweenSubmissions
    }

    static func recordSubmission() {
        UserDefaults.standard.set(Date(), forKey: key)
    }
}
