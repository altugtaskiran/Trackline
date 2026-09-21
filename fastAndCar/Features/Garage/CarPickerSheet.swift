//
//  CarPickerSheet.swift
//  fastAndCar
//
//  Searchable picker shared by AddCarView's Brand and Model fields — backed
//  by CarCatalog's static list, but never locks the user out: typing
//  something not in the list surfaces an "add as typed" row, since no
//  bundled list can cover every market variant/trim.
//

import SwiftUI

struct CarPickerSheet: View {
    let title: String
    let items: [String]
    var onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var filtered: [String] {
        trimmedQuery.isEmpty ? items : items.filter { $0.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    private var exactMatchExists: Bool {
        items.contains { $0.localizedCaseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                if !trimmedQuery.isEmpty && !exactMatchExists {
                    Button {
                        onSelect(trimmedQuery)
                        dismiss()
                    } label: {
                        Label("\"\(trimmedQuery)\" olarak ekle", systemImage: "plus.circle.fill")
                            .foregroundStyle(AppColor.accent)
                    }
                    .listRowBackground(AppColor.surface)
                }
                ForEach(filtered, id: \.self) { item in
                    Button {
                        onSelect(item)
                        dismiss()
                    } label: {
                        Text(item)
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    .listRowBackground(AppColor.surface)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppColor.background.ignoresSafeArea())
            .searchable(text: $query, prompt: "Ara veya yaz")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
