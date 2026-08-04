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
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(PersistenceController.shared)
    }
}
