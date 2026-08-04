//
//  Car.swift
//  fastAndCar
//
//  A car in the user's garage: photo + basic specs. Kept separate from Trip
//  for now — trips aren't tagged to a specific car yet, so this is a profile
//  page, not (yet) an aggregate-stats dashboard.
//

import Foundation
import SwiftData

enum FuelType: String, Codable, CaseIterable, Identifiable {
    case gasoline
    case diesel
    case electric
    case hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gasoline: "Benzin"
        case .diesel: "Dizel"
        case .electric: "Elektrik"
        case .hybrid: "Hibrit"
        }
    }
}

@Model
final class Car {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var make: String = ""
    var model: String = ""
    var year: Int = 2020
    var horsepower: Int = 0
    var fuelTypeRaw: String = FuelType.gasoline.rawValue
    var mileageKm: Int = 0
    var photoData: Data?

    var fuelType: FuelType {
        get { FuelType(rawValue: fuelTypeRaw) ?? .gasoline }
        set { fuelTypeRaw = newValue.rawValue }
    }

    var displayName: String { "\(make) \(model)" }

    init(make: String, model: String, year: Int, horsepower: Int, fuelType: FuelType, mileageKm: Int, photoData: Data?) {
        self.id = UUID()
        self.createdAt = Date()
        self.make = make
        self.model = model
        self.year = year
        self.horsepower = horsepower
        self.fuelTypeRaw = fuelType.rawValue
        self.mileageKm = mileageKm
        self.photoData = photoData
    }
}
