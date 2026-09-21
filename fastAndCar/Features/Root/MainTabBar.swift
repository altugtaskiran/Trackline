//
//  MainTabBar.swift
//  fastAndCar
//
//  Floating 3-segment bottom bar: Trips, Home (dashboard), Garage — a plain
//  tab switcher, all three aligned the same way. Starting a drive is a
//  deliberate tap on Dashboard's own button, never a side effect of tapping
//  this bar. Hidden entirely while a drive is active — see AppRootView — so
//  it never competes with the full-black recording screen.
//

import SwiftUI

struct MainTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.trips, systemImage: "clock.arrow.circlepath", label: "Sürüşlerim")
            tabButton(.routes, systemImage: "map.fill", label: "Rotalar")
            tabButton(.dashboard, systemImage: "location.fill", label: "Ana Sayfa", highlighted: true)
            tabButton(.garage, systemImage: "car.side.fill", label: "Garaj")
            tabButton(.community, systemImage: "trophy.fill", label: "Liderlik")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .overlay {
            Capsule().strokeBorder(AppColor.glassBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 4)
    }

    private func tabButton(_ tab: AppTab, systemImage: String, label: LocalizedStringKey, highlighted: Bool = false) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: highlighted ? 17 : 20))
                    .foregroundStyle(highlighted ? AppColor.background : (isSelected ? AppColor.textPrimary : AppColor.textTertiary))
                    .frame(width: 30, height: 30)
                    .background {
                        if highlighted {
                            Circle().fill(AppColor.accent)
                        }
                    }
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
