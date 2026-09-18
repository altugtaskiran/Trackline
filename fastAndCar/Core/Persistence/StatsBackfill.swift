//
//  StatsBackfill.swift
//  fastAndCar
//
//  One-time migration for trips saved before elevation/event stats existed.
//  Raw samples are still on disk (samplesData is untouched), so this just
//  re-runs TripStatsCalculator over them and writes the new fields back —
//  everything else about the trip stays as-is.
//

import Foundation
import SwiftData

enum StatsBackfill {
    static func run(context: ModelContext) {
        let descriptor = FetchDescriptor<Trip>()
        guard let trips = try? context.fetch(descriptor) else { return }

        var didChange = false
        for trip in trips {
            // A trip already has these fields once any of them is non-zero.
            // A drive that's genuinely flat with zero harsh events would
            // still read as "needs backfill" here, but re-running the
            // calculator on it is harmless and idempotent, so that's fine.
            let needsBackfill = trip.elevationGainMeters == 0
                && trip.elevationLossMeters == 0
                && trip.harshBrakeCount == 0
                && trip.harshAccelCount == 0
                && trip.corneringCount == 0
            guard needsBackfill else { continue }

            let samples = trip.samples
            guard samples.count > 1,
                  let stats = TripStatsCalculator.calculate(samples: samples, stopEvents: trip.stopEvents) else { continue }
            trip.applyBackfilledStats(stats)
            didChange = true
        }

        if didChange {
            try? context.save()
        }
    }
}
