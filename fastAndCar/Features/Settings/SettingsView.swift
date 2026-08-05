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
    var label: String { self == .kilometers ? String.appLocalized("Kilometre") : String.appLocalized("Mil") }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SettingsViewModel
    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.kilometers.rawValue
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.system.rawValue
    #if DEBUG
    @State private var debugAutoOpenLanguage = false
    #endif

    init(locationManager: LocationManager) {
        _viewModel = State(initialValue: SettingsViewModel(locationManager: locationManager))
    }

    private var distanceUnit: Binding<DistanceUnit> {
        Binding(
            get: { DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers },
            set: { distanceUnitRaw = $0.rawValue }
        )
    }

    private var appLanguage: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: appLanguageRaw) ?? .system },
            set: { appLanguageRaw = $0.rawValue }
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

                        GlassCard(padding: 0) {
                            NavigationLink {
                                LanguagePickerView(selection: appLanguage)
                            } label: {
                                HStack {
                                    Text("Dil")
                                        .font(AppFont.headline)
                                        .foregroundStyle(AppColor.textPrimary)
                                    Spacer()
                                    Text(appLanguage.wrappedValue.label)
                                        .font(AppFont.body)
                                        .foregroundStyle(AppColor.textSecondary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AppColor.textTertiary)
                                }
                                .padding(16)
                            }
                            .buttonStyle(.plain)
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
            #if DEBUG
            .navigationDestination(isPresented: $debugAutoOpenLanguage) {
                LanguagePickerView(selection: appLanguage)
            }
            #endif
        }
        .preferredColorScheme(.dark)
        #if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoLanguage") else { return }
            try? await Task.sleep(for: .seconds(1))
            debugAutoOpenLanguage = true
        }
        #endif
    }
}
