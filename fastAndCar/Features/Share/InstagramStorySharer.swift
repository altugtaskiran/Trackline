//
//  InstagramStorySharer.swift
//  fastAndCar
//
//  "Share to Instagram Stories" as a custom UIActivity, so it shows up as
//  one more icon inside the native share sheet (next to Messages, Mail,
//  WhatsApp, …) instead of a separate button — one "Paylaş" action reaches
//  every destination. Uses Meta's documented pasteboard + URL-scheme
//  handoff for third-party apps; no Facebook SDK dependency needed.
//  Requires "instagram-stories" in LSApplicationQueriesSchemes
//  (Config/Info.plist) so canOpenURL can see the app is installed.
//

import UIKit

final class InstagramStoryActivity: UIActivity {
    private let image: UIImage

    init(image: UIImage) {
        self.image = image
        super.init()
    }

    override var activityTitle: String? { "Instagram Hikayesi" }
    override var activityImage: UIImage? { UIImage(systemName: "camera.fill") }
    override var activityType: UIActivity.ActivityType? { UIActivity.ActivityType("com.fastandcar.share.instagramStory") }
    override class var activityCategory: UIActivity.Category { .share }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        guard let url = URL(string: "instagram-stories://share") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    override func perform() {
        defer { activityDidFinish(true) }
        guard let pngData = image.pngData(), let url = URL(string: "instagram-stories://share") else { return }

        let pasteboardItems: [String: Any] = [
            "com.instagram.sharedSticker.backgroundImage": pngData,
        ]
        UIPasteboard.general.setItems(
            [pasteboardItems],
            options: [.expirationDate: Date().addingTimeInterval(300)]
        )
        UIApplication.shared.open(url)
    }
}
