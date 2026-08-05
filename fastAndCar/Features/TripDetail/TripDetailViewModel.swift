//
//  TripDetailViewModel.swift
//  fastAndCar
//
//  Drives the trip detail screen: exposes precomputed stats/score, and owns
//  the playback cursor + route-inspector selection so the view stays dumb.
//

import Foundation
import Observation

@Observable
final class TripDetailViewModel {
    let trip: Trip
    let samples: [LocationSample]

    var inspectedIndex: Int?

    // Playback drives the same map marker a tap does — scrubbing or hitting
    // play must move the inspected point along the route in lockstep, not
    // just update the stat readouts.
    private(set) var playbackIndex: Int = 0 {
        didSet { inspectedIndex = playbackIndex }
    }
    private(set) var isPlaying = false
    private var playbackTimer: Timer?
    /// How many samples to advance per tick so total playback time stays
    /// roughly constant (~20s) regardless of trip length.
    private var stepsPerTick: Int { max(1, samples.count / 400) }

    init(trip: Trip) {
        self.trip = trip
        self.samples = trip.samples
    }

    var stopEvents: [TripStopEvent] { trip.stopEvents }
    var stats: TripStats { trip.stats }
    var score: DrivingScore { trip.drivingScore }

    var playbackProgress: Double {
        guard samples.count > 1 else { return 0 }
        return Double(playbackIndex) / Double(samples.count - 1)
    }

    var playbackSample: LocationSample? {
        samples.indices.contains(playbackIndex) ? samples[playbackIndex] : nil
    }

    var playbackElapsed: TimeInterval {
        guard let first = samples.first, let current = playbackSample else { return 0 }
        return current.timestamp.timeIntervalSince(first.timestamp)
    }

    var playbackDistanceMeters: Double {
        guard playbackIndex > 0, samples.count > playbackIndex else { return 0 }
        var distance = 0.0
        for index in 1...playbackIndex {
            distance += GeoMath.distanceMeters(from: samples[index - 1].coordinate, to: samples[index].coordinate)
        }
        return distance
    }

    var inspectedSample: LocationSample? {
        guard let inspectedIndex, samples.indices.contains(inspectedIndex) else { return nil }
        return samples[inspectedIndex]
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard samples.count > 1 else { return }
        if playbackIndex >= samples.count - 1 { playbackIndex = 0 }
        isPlaying = true
        Haptics.light()
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.advancePlayback()
        }
    }

    func pause() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    func seek(toProgress progress: Double) {
        guard samples.count > 1 else { return }
        pause()
        let index = Int((progress * Double(samples.count - 1)).rounded())
        playbackIndex = min(max(index, 0), samples.count - 1)
    }

    func renameStopEvent(id: UUID, label: String) {
        trip.renameStopEvent(id: id, to: label)
    }

    private func advancePlayback() {
        guard playbackIndex < samples.count - 1 else {
            pause()
            return
        }
        playbackIndex = min(playbackIndex + stepsPerTick, samples.count - 1)
    }
}

