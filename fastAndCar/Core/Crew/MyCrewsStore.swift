//
//  MyCrewsStore.swift
//  fastAndCar
//
//  Local cache of every Crew this device belongs to (created or joined),
//  each paired with the CrewZoneRef needed to read/write its records —
//  same pragmatic local-index pattern as MyCreatedSegmentsStore, avoiding a
//  live CloudKit round trip just to list "my crews" on every tab open.
//

import Foundation
import Observation

struct MyCrewRef: Codable, Identifiable {
    let crew: Crew
    let zoneRef: CrewZoneRef
    var id: String { crew.id }
}

@Observable
final class MyCrewsStore {
    private static let key = "myCrews"

    private(set) var crews: [MyCrewRef]

    init() {
        crews = Self.load()
    }

    func record(_ crew: Crew, zoneRef: CrewZoneRef) {
        crews.removeAll { $0.crew.id == crew.id }
        crews.insert(MyCrewRef(crew: crew, zoneRef: zoneRef), at: 0)
        save()
    }

    func remove(_ crewId: String) {
        crews.removeAll { $0.crew.id == crewId }
        save()
    }

    private static func load() -> [MyCrewRef] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([MyCrewRef].self, from: data) else { return [] }
        return decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(crews) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
