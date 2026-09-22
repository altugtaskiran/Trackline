//
//  CrewPresenceBroadcaster.swift
//  fastAndCar
//
//  Drives LocationManager's presence-only location stream and, while the
//  Settings toggle is on, throttles writes of the current coordinate into
//  every crew the user belongs to — independent of trip recording. Off by
//  default; nothing here runs unless the user explicitly opts in.
//

import Foundation
import Observation

@MainActor
@Observable
final class CrewPresenceBroadcaster {
    private let locationManager: LocationManager
    private var pollTask: Task<Void, Never>?
    private var lastBroadcastAt: Date?
    /// Don't hit CloudKit on every GPS tick — throttled to one write per
    /// crew per ~8s. Was 20s; confirmed live that the longer interval made
    /// crew members feel like they were "jumping" on the map with long
    /// silent gaps. 8s is still far from every-tick, but tracks noticeably
    /// smoother while a drive is in progress.
    private let minBroadcastInterval: TimeInterval = 8

    /// Plain-language status, visible in Settings — the only way to
    /// diagnose a silent failure on a TestFlight (Release) build, where
    /// #if DEBUG hooks and Xcode's console aren't available to the user.
    private(set) var lastStatus: String = "Kapalı"

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
    }

    func start() {
        guard pollTask == nil else { return }
        guard locationManager.hasUsableAuthorization else {
            lastStatus = "Konum izni verilmedi"
            return
        }
        locationManager.startBroadcastingPresence()
        lastStatus = "Konum bekleniyor…"
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.broadcastIfNeeded()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        locationManager.stopBroadcastingPresence()
        lastStatus = "Kapalı"
    }

    private func broadcastIfNeeded() async {
        guard let sample = locationManager.latestSample else {
            lastStatus = "Konum bekleniyor…"
            return
        }
        if let lastBroadcastAt, Date().timeIntervalSince(lastBroadcastAt) < minBroadcastInterval { return }
        lastBroadcastAt = Date()

        guard let userId = try? await CloudKitCrewService.currentUserId() else {
            lastStatus = "iCloud hesabı bulunamadı"
            return
        }
        let crews = MyCrewsStore().crews
        guard !crews.isEmpty else {
            lastStatus = "Henüz bir crew'a üye değilsin"
            return
        }
        var failure: String?
        for crewRef in crews {
            do {
                try await CloudKitCrewService.updateMyLocation(
                    coordinate: sample.coordinate,
                    userId: userId,
                    crewId: crewRef.crew.id,
                    zoneRef: crewRef.zoneRef
                )
            } catch {
                failure = error.localizedDescription
            }
        }
        lastStatus = failure.map { "Hata: \($0)" } ?? "Gönderildi · \(Date().formatted(date: .omitted, time: .shortened))"
    }
}
