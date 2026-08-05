//
//  PlaceNameResolver.swift
//  fastAndCar
//
//  Reverse-geocodes a trip's start/end coordinates into "City, Country"
//  labels for Home's trip rows — country rather than province/state so the
//  label reads sensibly anywhere in the world, not just Turkey. Best-effort —
//  returns nil on failure (no network, rate limited, etc.) and callers fall
//  back to showing the date.
//

import CoreLocation
import MapKit

enum PlaceNameResolver {
    static func resolve(coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        guard let mapItem = try? await request.mapItems.first else { return nil }
        return format(city: mapItem.addressRepresentations?.cityName, country: mapItem.addressRepresentations?.regionName)
    }

    private static func format(city: String?, country: String?) -> String? {
        let city = city?.trimmingCharacters(in: .whitespaces)
        let country = country?.trimmingCharacters(in: .whitespaces)

        switch (city, country) {
        case let (city?, country?) where !city.isEmpty && !country.isEmpty && city != country:
            return "\(city), \(country)"
        case let (city?, _) where !city.isEmpty:
            return city
        case let (_, country?) where !country.isEmpty:
            return country
        default:
            return nil
        }
    }
}
