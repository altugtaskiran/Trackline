//
//  ProfilePhotoCache.swift
//  fastAndCar
//
//  In-memory, session-lifetime cache of other users' leaderboard profile
//  photos — segment/crew leaderboard screens prefetch once per load instead
//  of every row independently re-fetching the same userId's photo.
//

import Observation
import UIKit

@Observable
final class ProfilePhotoCache {
    static let shared = ProfilePhotoCache()

    private var images: [String: UIImage] = [:]
    private init() {}

    func image(for userId: String) -> UIImage? { images[userId] }

    /// Best-effort and silent — same posture as every other CloudKit read in
    /// this app (SegmentAutoMatcher, GlobalLeaderboardListView): missing
    /// photos or an offline/feature-gated fetch just leave rows without an
    /// avatar, never blocks or surfaces an error.
    func prefetch(userIds: [String]) async {
        let missing = Set(userIds).subtracting(images.keys)
        guard !missing.isEmpty else { return }
        guard let fetched = try? await CloudKitProfileService.fetchPhotos(userIds: Array(missing)) else { return }
        for (userId, data) in fetched {
            guard let image = UIImage(data: data) else { continue }
            images[userId] = image
        }
    }
}
