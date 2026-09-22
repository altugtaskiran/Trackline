//
//  CrewLiveMapView.swift
//  fastAndCar
//
//  A small live map showing where a crew's currently-active members are —
//  each pin is that person's avatar in a colored ring. Pure presentation:
//  the caller (CrewDetailView) owns fetching/polling CrewLiveLocation and
//  passes the current snapshot in, so the roster's green dots and this map
//  share one data source instead of polling twice.
//

import MapKit
import SwiftUI

struct CrewLiveMapView: View {
    let members: [CrewMembership]
    let locations: [CrewLiveLocation]
    var photoCache: ProfilePhotoCache = .shared

    @State private var cameraPosition: MapCameraPosition = .automatic

    private var activeLocations: [(member: CrewMembership, location: CrewLiveLocation)] {
        locations.filter(\.isActive).compactMap { location in
            guard let member = members.first(where: { $0.userId == location.userId }) else { return nil }
            return (member, location)
        }
    }

    var body: some View {
        Group {
            if activeLocations.isEmpty {
                emptyState
            } else {
                Map(position: $cameraPosition) {
                    ForEach(activeLocations, id: \.member.userId) { entry in
                        Annotation(entry.member.nickname, coordinate: entry.location.coordinate) {
                            ZStack {
                                Circle().fill(AppColor.accent.opacity(0.15)).frame(width: 44, height: 44)
                                AvatarView(image: photoCache.image(for: entry.member.userId), initial: entry.member.nickname.first, size: 34)
                                    .overlay(Circle().strokeBorder(AppColor.accent, lineWidth: 2))
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
                .onAppear { fitCamera() }
                .onChange(of: activeLocations.map(\.location.coordinate.latitude)) { _, _ in fitCamera() }
            }
        }
        .frame(height: 220)
        .glassCard(cornerRadius: 22, padding: 0)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.slash")
                .font(.system(size: 24))
                .foregroundStyle(AppColor.textTertiary)
            Text("Şu an aktif üye yok")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func fitCamera() {
        let coordinates = activeLocations.map(\.location.coordinate)
        guard !coordinates.isEmpty else { return }
        let region = FittedRegion.fitting(
            samples: coordinates.map { LocationSample(coordinate: $0, timestamp: Date(), speedMps: 0, altitude: 0, heading: nil, horizontalAccuracy: 0) },
            aspectRatio: 1
        )
        withAnimation { cameraPosition = .region(region) }
    }
}
