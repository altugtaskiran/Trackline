//
//  CrewShareAppDelegate.swift
//  fastAndCar
//
//  SwiftUI's WindowGroup lifecycle has no direct hook for "a user tapped a
//  CKShare invite link" — that's still only delivered to
//  UIApplicationDelegate, so this minimal delegate exists solely to catch
//  it and hand off to CloudKitCrewService. CrewInviteAcceptance is the
//  bridge back into SwiftUI: CrewHomeView observes it to refresh the
//  moment a new crew's membership finishes writing.
//

import CloudKit
import Observation
import UIKit

@Observable
final class CrewInviteAcceptance {
    static let shared = CrewInviteAcceptance()
    var lastAcceptedCrew: Crew?
    var errorMessage: String?
}

final class CrewShareAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task {
            do {
                let userId = try await CloudKitCrewService.currentUserId()
                let nickname = NicknameStore().nickname
                let (crew, zoneRef) = try await CloudKitCrewService.acceptShare(metadata: metadata, userId: userId, nickname: nickname)
                MyCrewsStore().record(crew, zoneRef: zoneRef)
                CrewInviteAcceptance.shared.lastAcceptedCrew = crew
                LocalNotifier.notifyCrewJoined(crewName: crew.name)
            } catch {
                CrewInviteAcceptance.shared.errorMessage = "Davet kabul edilemedi. Bağlantını kontrol edip tekrar dene."
            }
        }
    }
}
