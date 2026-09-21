//
//  CommunityView.swift
//  fastAndCar
//
//  "Liderlik" tab, one roof over both social features: user-defined
//  Segments' Global Leaderboard and Crew's post-drive comparison. A
//  segmented control rather than two separate tabs — MainTabBar's floating
//  capsule was already stretched thin before "Rotalar" made it five.
//

import SwiftUI

private enum CommunitySection: String, CaseIterable, Identifiable {
    case global
    case crew
    var id: String { rawValue }

    var label: String {
        switch self {
        case .global: String.appLocalized("Global")
        case .crew: String.appLocalized("Crew")
        }
    }
}

struct CommunityView: View {
    @State private var section: CommunitySection = .global
    var onFollowSegment: (Segment) -> Void
    var onFollowCrewSegment: (Segment, CrewZoneRef) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                ForEach(CommunitySection.allCases) { section in
                    Text(section.label).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Group {
                switch section {
                case .global:
                    GlobalLeaderboardListView(onFollowSegment: onFollowSegment)
                case .crew:
                    CrewHomeView(onFollowCrewSegment: onFollowCrewSegment)
                }
            }
        }
        .background(AppColor.background.ignoresSafeArea())
    }
}
