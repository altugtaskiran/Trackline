//
//  ProfilePhotoCache.swift
//  fastAndCar
//
//  In-memory cache of other users' leaderboard profile photos —
//  segment/crew leaderboard screens prefetch once per load instead of every
//  row independently re-fetching the same userId's photo. Also backed by a
//  small disk cache (Caches directory) so a fresh app launch doesn't have
//  to re-download every crewmate/leaderboard photo from CloudKit again —
//  it was previously memory-only, wiped on every relaunch.
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

        var stillMissing: [String] = []
        for userId in missing {
            if let diskImage = loadFromDisk(userId: userId) {
                images[userId] = diskImage
            } else {
                stillMissing.append(userId)
            }
        }
        guard !stillMissing.isEmpty else { return }

        guard let fetched = try? await CloudKitProfileService.fetchPhotos(userIds: stillMissing) else { return }
        for (userId, data) in fetched {
            guard let image = UIImage(data: data) else { continue }
            images[userId] = image
            saveToDisk(userId: userId, data: data)
        }
    }

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProfilePhotos", isDirectory: true)
    }

    private func diskURL(for userId: String) -> URL {
        cacheDirectory.appendingPathComponent(userId)
    }

    private func loadFromDisk(userId: String) -> UIImage? {
        guard let data = try? Data(contentsOf: diskURL(for: userId)) else { return nil }
        return UIImage(data: data)
    }

    private func saveToDisk(userId: String, data: Data) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: diskURL(for: userId))
    }
}
