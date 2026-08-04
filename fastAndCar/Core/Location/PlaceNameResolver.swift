//
//  PlaceNameResolver.swift
//  fastAndCar
//
//  Reverse-geocodes a trip's start/end coordinates into "City, Province"
//  labels for Home's trip rows. Best-effort — returns nil on failure (no
//  network, rate limited, etc.) and callers fall back to showing the date.
//

import CoreLocation

enum PlaceNameResolver {
    private static let geocoder = CLGeocoder()

    static func resolve(coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
        return format(locality: placemark.locality, administrativeArea: placemark.administrativeArea)
    }

    private static func format(locality: String?, administrativeArea: String?) -> String? {
        let city = locality?.trimmingCharacters(in: .whitespaces)
        let province = administrativeArea?.trimmingCharacters(in: .whitespaces)

        switch (city, province) {
        case let (city?, province?) where !city.isEmpty && !province.isEmpty && city != province:
            return "\(city), \(province)"
        case let (city?, _) where !city.isEmpty:
            return city
        case let (_, province?) where !province.isEmpty:
            return province
        default:
            return nil
        }
    }
}
