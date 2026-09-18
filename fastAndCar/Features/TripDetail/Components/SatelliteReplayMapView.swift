//
//  SatelliteReplayMapView.swift
//  fastAndCar
//
//  Faz 2 spike — an alternative to RouteCanvas's flat "F1 track map" replay:
//  a live MapKit camera in hybrid satellite + realistic elevation, following
//  the same playback cursor (TripDetailViewModel.playbackIndex) frame for
//  frame. Both renderers share one time cursor; this is purely a second view
//  onto it, never a second source of truth for "where is playback right now."
//
//  MapKit's realistic elevation/3D buildings only render in the regions
//  Apple has modeled — outside those, this still shows correct satellite
//  imagery and camera motion, just without the extra terrain relief.
//

import MapKit
import SwiftUI

struct SatelliteReplayMapView: View {
    var viewModel: TripDetailViewModel

    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $cameraPosition, interactionModes: []) {
            if let sample = viewModel.playbackSample {
                Annotation("", coordinate: sample.coordinate) {
                    Circle()
                        .fill(AppColor.accent)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .onAppear { updateCamera(animated: false) }
        .onChange(of: viewModel.playbackIndex) { _, _ in updateCamera(animated: true) }
    }

    private func updateCamera(animated: Bool) {
        guard let sample = viewModel.playbackSample else { return }
        let camera = MapCamera(
            centerCoordinate: sample.coordinate,
            distance: 350,
            heading: sample.heading ?? 0,
            pitch: 60
        )
        if animated {
            withAnimation(.linear(duration: 0.15)) {
                cameraPosition = .camera(camera)
            }
        } else {
            cameraPosition = .camera(camera)
        }
    }
}
