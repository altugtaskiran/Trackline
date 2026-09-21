//
//  AvatarView.swift
//  fastAndCar
//
//  Circular leaderboard avatar — the uploaded profile photo when one's been
//  fetched (ProfilePhotoCache), otherwise a monogram fallback so a row never
//  looks broken/empty while photos are still loading or simply weren't set.
//

import SwiftUI

struct AvatarView: View {
    let image: UIImage?
    let initial: Character?
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    AppColor.accent.opacity(0.18)
                    Text(initial.map(String.init)?.uppercased() ?? "?")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(AppColor.accent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(AppColor.glassBorderSubtle, lineWidth: 1))
    }
}
