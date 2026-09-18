//
//  PersistenceController.swift
//  fastAndCar
//
//  Single shared SwiftData container for the app.
//

import Foundation
import SwiftData

enum PersistenceController {
    static let shared: ModelContainer = {
        do {
            let container = try ModelContainer(for: Trip.self, Car.self)
            StatsBackfill.run(context: ModelContext(container))
            return container
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
