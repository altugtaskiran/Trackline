//
//  LocationMarkerStyle.swift
//  fastAndCar
//
//  What the "you are here" marker looks like on the live/idle maps —
//  Settings > Konum İşareti. Default is the plain dot (what every user
//  sees unless they opt in); additional car options get added here as
//  they're designed/licensed, without touching the rendering call sites.
//

import Foundation

enum LocationMarkerStyle: String, CaseIterable, Identifiable {
    case dot
    case carTest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dot: String.appLocalized("Varsayılan")
        case .carTest: String.appLocalized("Araç (Test)")
        }
    }

    static var current: LocationMarkerStyle {
        let raw = UserDefaults.standard.string(forKey: "locationMarkerStyle") ?? LocationMarkerStyle.dot.rawValue
        return LocationMarkerStyle(rawValue: raw) ?? .dot
    }
}
