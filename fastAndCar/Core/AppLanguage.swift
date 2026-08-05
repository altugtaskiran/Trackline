//
//  AppLanguage.swift
//  fastAndCar
//
//  In-app language override, independent of the device's system language —
//  Settings > Language. "system" means "don't override", so the app follows
//  whatever the device is set to among the languages it ships.
//
//  SwiftUI's `.environment(\.locale, ...)` (applied once at the AppRootView
//  root) is what makes every plain `Text("literal")` in the app pick up the
//  override automatically. It does *not* reach plain Foundation calls like
//  `String(localized:)` made outside a View's body (view models, enums) —
//  those go through `String.appLocalized(_:)` below instead, which reads the
//  same stored preference directly.
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case tr
    case en

    var id: String { rawValue }

    static var current: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue
        return AppLanguage(rawValue: raw) ?? .system
    }

    var label: String {
        switch self {
        case .system: String.appLocalized("Sistem")
        case .tr: String.appLocalized("Türkçe")
        case .en: String.appLocalized("İngilizce")
        }
    }

    var locale: Locale? {
        switch self {
        case .system: nil
        case .tr: Locale(identifier: "tr")
        case .en: Locale(identifier: "en")
        }
    }
}

extension String {
    /// Same lookup as `String(localized:)`, but honors the Settings >
    /// Language override for call sites that aren't inside a View body (and
    /// so can't just rely on the `.environment(\.locale, ...)` SwiftUI
    /// applies at the root). `String(localized:locale:)`'s `locale:`
    /// parameter does *not* actually pick which language variant of a
    /// String Catalog gets read (it only affects locale-aware formatting) —
    /// loading the specific .lproj bundle by hand is what reliably forces
    /// the language regardless of the device's own system language.
    static func appLocalized(_ key: String) -> String {
        guard let code = AppLanguage.current.locale?.identifier,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let languageBundle = Bundle(path: path) else {
            return NSLocalizedString(key, comment: "")
        }
        return NSLocalizedString(key, bundle: languageBundle, comment: "")
    }
}
