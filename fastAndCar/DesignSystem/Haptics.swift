//
//  Haptics.swift
//  fastAndCar
//
//  Centralized haptic feedback so feel stays consistent across key moments.
//

import UIKit

enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func tripStarted() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    static func tripEnded() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
