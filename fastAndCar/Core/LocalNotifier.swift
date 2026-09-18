//
//  LocalNotifier.swift
//  fastAndCar
//
//  Thin wrapper over UNUserNotificationCenter for the app's few background
//  "something happened while you weren't looking" moments — a drive
//  matching a Global Leaderboard segment, a Crew invite being accepted.
//  Local only (no push server involved), but still needs the delegate set
//  so a notification actually shows while the app is in the foreground,
//  which is the common case right after ending a drive.
//

import Foundation
import Observation
import UserNotifications

@Observable
final class LocalNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LocalNotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

enum LocalNotifier {
    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    static func notifySegmentMatches(names: [String]) {
        guard !names.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = String.appLocalized("Parkur Eşleşmesi")
        content.body = names.count == 1
            ? String(format: String.appLocalized("\"%@\" parkurunu tamamladın!"), names[0])
            : String(format: String.appLocalized("%d parkur tamamladın!"), names.count)
        content.sound = .default
        post(content)
    }

    static func notifyCrewJoined(crewName: String) {
        let content = UNMutableNotificationContent()
        content.title = String.appLocalized("Crew'a Katıldın")
        content.body = String(format: String.appLocalized("\"%@\" crew'ına katıldın."), crewName)
        content.sound = .default
        post(content)
    }

    static func notifyAchievementUnlocked(title: String) {
        let content = UNMutableNotificationContent()
        content.title = String.appLocalized("Yeni Rozet")
        content.body = String(format: String.appLocalized("\"%@\" rozetini kazandın!"), title)
        content.sound = .default
        post(content)
    }

    private static func post(_ content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
