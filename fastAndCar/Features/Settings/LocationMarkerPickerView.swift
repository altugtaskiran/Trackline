//
//  LocationMarkerPickerView.swift
//  fastAndCar
//
//  Konum Göstergesi — a bottom sheet listing every "you are here" marker
//  option (row: icon, name, checkmark if selected), same shape as
//  Yandex Navigator's own vehicle-icon picker. The default green dot is
//  always the top row; new car options just get another case added to
//  LocationMarkerStyle, no changes needed here.
//

import SwiftUI

struct LocationMarkerPickerView: View {
    @Binding var selection: LocationMarkerStyle
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Konum Göstergesi")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)

            VStack(spacing: 0) {
                ForEach(LocationMarkerStyle.allCases) { style in
                    Button {
                        selection = style
                        onDismiss()
                    } label: {
                        HStack(spacing: 16) {
                            icon(for: style)
                            Text(style.label)
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                            Spacer()
                            if selection == style {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(AppColor.accent)
                            }
                        }
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if style != LocationMarkerStyle.allCases.last {
                        Divider().overlay(AppColor.glassBorderSubtle)
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func icon(for style: LocationMarkerStyle) -> some View {
        switch style {
        case .dot:
            Circle()
                .fill(AppColor.accent)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(.white, lineWidth: 2))
        case .carTest:
            Image("LocationCar")
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
        }
    }
}
