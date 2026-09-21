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
    private static let tagKey = "leaderboardTag"

    var nickname: String {
        didSet { UserDefaults.standard.set(nickname, forKey: Self.key) }
    }

    /// A stable 4-digit suffix ("turbo #4823") — generated once and kept
    /// forever, so a friend can find this exact person even if several
    /// people pick the same nickname. Random rather than sequential: no
    /// server-side counter to coordinate, and collisions across ~9000
    /// possible values are rare enough for a friends-and-crew feature.
    /// var, not let — restore(nickname:tag:) can overwrite it after a
    /// delete-and-reinstall recovers the old handle from CloudKit, so a
    /// fresh install never orphans a tag friends already have saved.
    private(set) var tag: Int

    var hasNickname: Bool { !nickname.trimmingCharacters(in: .whitespaces).isEmpty }

    var handle: String { "\(nickname)#\(tag)" }

    init() {
        nickname = UserDefaults.standard.string(forKey: Self.key) ?? ""
        if UserDefaults.standard.object(forKey: Self.tagKey) != nil {
            tag = UserDefaults.standard.integer(forKey: Self.tagKey)
        } else {
            let generated = Int.random(in: 1000...9999)
            UserDefaults.standard.set(generated, forKey: Self.tagKey)
            tag = generated
        }
    }

    /// Overwrites both nickname and tag with values recovered from
    /// CloudKit (see CloudKitProfileService.fetchMyHandle) — used right
    /// after a fresh install/reinstall, before this device's own random
    /// tag has been synced anywhere, so the recovered identity wins.
    func restore(nickname: String, tag: Int) {
        self.nickname = nickname
        self.tag = tag
        UserDefaults.standard.set(tag, forKey: Self.tagKey)
    }
}
