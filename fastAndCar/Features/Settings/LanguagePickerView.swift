//
//  LanguagePickerView.swift
//  fastAndCar
//
//  A scrolling List rather than a segmented control — AppLanguage only has
//  three cases today (System/Türkçe/English), but a List scales to however
//  many more languages land in later phases without a redesign; a segmented
//  control would just get cramped.
//

import SwiftUI

struct LanguagePickerView: View {
    @Binding var selection: AppLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    selection = language
                    dismiss()
                } label: {
                    HStack {
                        Text(language.label)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        if selection == language {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColor.accent)
                        }
                    }
                }
                .listRowBackground(AppColor.surface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Dil")
        .navigationBarTitleDisplayMode(.inline)
    }
}
