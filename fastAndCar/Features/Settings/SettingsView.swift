//
//  SettingsView.swift
//  fastAndCar
//
//  Minimal by design: permission status, distance unit, app version. Reached
//  from a small icon on Home rather than a tab bar.
//

import SwiftUI

enum DistanceUnit: String, CaseIterable, Identifiable {
    case kilometers, miles
    var id: String { rawValue }
    var label: String { self == .kilometers ? "Kilometre" : "Mil" }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SettingsViewModel
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.kilometers.rawValue

    init(locationManager: LocationManager) {
        _viewModel = State(initialValue: SettingsViewModel(locationManager: locationManager))
    }

    private var distanceUnit: Binding<DistanceUnit> {
        Binding(
            get: { DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers },
            set: { distanceUnitRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        GlassCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Konum İzni")
                                        .font(AppFont.headline)
                                        .foregroundStyle(AppColor.textPrimary)
                                    Text(viewModel.authorizationStatusText)
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.textSecondary)
                                }
                                Spacer()
                                Circle()
                                    .fill(viewModel.authorizationIsGranted ? AppColor.accent : Color(hex: 0xFF3B30))
                                    .frame(width: 10, height: 10)
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Mesafe Birimi")
                                    .font(AppFont.headline)
                                    .foregroundStyle(AppColor.textPrimary)
                                Picker("Mesafe Birimi", selection: distanceUnit) {
                                    ForEach(DistanceUnit.allCases) { unit in
                                        Text(unit.label).tag(unit)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }

                        GlassCard {
                            HStack {
                                Text("Sürüm")
                                    .font(AppFont.body)
                                    .foregroundStyle(AppColor.textSecondary)
                                Spacer()
                                Text(viewModel.appVersion)
                                    .font(AppFont.body)
                                    .foregroundStyle(AppColor.textPrimary)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(AppColor.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
