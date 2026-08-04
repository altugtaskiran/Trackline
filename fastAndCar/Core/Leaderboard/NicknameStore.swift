//
//  NicknameStore.swift
//  fastAndCar
//
//  The display name attached to leaderboard submissions. Asked once, kept
//  locally — no separate account/password system, CloudKit's implicit
//  iCloud identity handles "who can write what."
//

import Foundation
import Observation

@Observable
final class NicknameStore {
    private static let key = "leaderboardNickname"

    var nickname: String {
        didSet { UserDefaults.standard.set(nickname, forKey: Self.key) }
    }

    var hasNickname: Bool { !nickname.trimmingCharacters(in: .whitespaces).isEmpty }

    init() {
        nickname = UserDefaults.standard.string(forKey: Self.key) ?? ""
    }
}
