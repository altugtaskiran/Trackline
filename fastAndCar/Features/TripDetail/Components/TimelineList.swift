//
//  TimelineList.swift
//  fastAndCar
//
//  Start / stop / finish events as a vertical timeline. Tapping a stop lets
//  the user rename it (e.g. "Stop" → "Fuel Stop").
//

import SwiftUI

private struct TimelineEntry: Identifiable {
    let id: UUID
    let time: Date
    let title: String
    let subtitle: String?
    let stopEventID: UUID?
}

struct TimelineList: View {
    let trip: Trip
    let stopEvents: [TripStopEvent]
    var onRename: (UUID, String) -> Void

    @State private var editingEventID: UUID?
    @State private var editingLabel = ""

    private var entries: [TimelineEntry] {
        var result: [TimelineEntry] = [
            TimelineEntry(id: UUID(), time: trip.startTime, title: "Started", subtitle: nil, stopEventID: nil),
        ]
        for event in stopEvents {
            result.append(
                TimelineEntry(
                    id: event.id,
                    time: event.startTime,
                    title: event.label,
                    subtitle: event.duration.map(formatDuration),
                    stopEventID: event.id
                )
            )
        }
        result.append(TimelineEntry(id: UUID(), time: trip.finishTime, title: "Finished", subtitle: nil, stopEventID: nil))
        return result.sorted { $0.time < $1.time }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(entry.stopEventID == nil ? AppColor.accent : AppColor.textTertiary)
                            .frame(width: 8, height: 8)
                        if index < entries.count - 1 {
                            Rectangle()
                                .fill(AppColor.glassBorder)
                                .frame(width: 1)
                                .frame(minHeight: 30)
                        }
                    }
                    .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.time.formatted(date: .omitted, time: .shortened))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                        HStack(spacing: 4) {
                            // "Started"/"Finished"/the default "Stop" label
                            // are catalog keys; a user-renamed stop is free
                            // text that just won't match any key and renders
                            // as-is.
                            Text(LocalizedStringKey(entry.title))
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.textPrimary)
                            if let subtitle = entry.subtitle {
                                Text("· \(subtitle)")
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            if entry.stopEventID != nil {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppColor.textTertiary)
                            }
                        }
                    }
                    .padding(.bottom, 18)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard let stopEventID = entry.stopEventID else { return }
                        editingLabel = entry.title
                        editingEventID = stopEventID
                    }

                    Spacer()
                }
            }
        }
        .alert(
            "Durağı Adlandır",
            isPresented: Binding(
                get: { editingEventID != nil },
                set: { isPresented in if !isPresented { editingEventID = nil } }
            )
        ) {
            TextField("Örn. Yakıt Molası", text: $editingLabel)
            Button("Kaydet") {
                if let id = editingEventID {
                    onRename(id, editingLabel)
                }
                editingEventID = nil
            }
            Button("Vazgeç", role: .cancel) { editingEventID = nil }
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        return minutes > 0 ? "\(minutes)m" : "<1m"
    }
}
