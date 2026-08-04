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
            return try ModelContainer(for: Trip.self, Car.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
