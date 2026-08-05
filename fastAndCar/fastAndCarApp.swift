//
//  fastAndCarApp.swift
//  fastAndCar
//
//  Created by Altuğ Taşkıran on 4.08.2026.
//

import SwiftData
import SwiftUI

@main
struct fastAndCarApp: App {
    // Settings > Language override, read again at the scene root. Applying
    // it only inside AppRootView's own view tree left it invisible to
    // .navigationDestination pushes and .sheet presentations — both open a
    // presentation context that doesn't reliably inherit environment values
    // set further up inside the same view, only ones set at (or above) the
    // WindowGroup that hosts the whole scene.
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.system.rawValue

    var body: some Scene {
        WindowGroup {
            // "System" must skip the modifier entirely rather than pin
            // \.locale to Locale.autoupdatingCurrent — the two aren't the
            // same. With no override, SwiftUI picks a language by matching
            // the device's full ranked AppleLanguages list against the
            // app's supported languages; pinning to autoupdatingCurrent
            // instead resolves off a single current locale, which isn't
            // guaranteed to agree (it didn't in testing: a tr-first, en-
            // second device resolved to English once pinned).
            if let locale = (AppLanguage(rawValue: appLanguageRaw) ?? .system).locale {
                AppRootView().environment(\.locale, locale)
            } else {
                AppRootView()
            }
        }
        .modelContainer(PersistenceController.shared)
    }
}
