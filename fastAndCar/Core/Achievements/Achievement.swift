//
//  Achievement.swift
//  fastAndCar
//
//  Faz 4 — a fixed local badge catalog. No CloudKit dependency at all
//  (unlike Global Leaderboard/Crew), so this ships fully working today
//  instead of sitting behind FeatureFlags.
//

import Foundation

struct Achievement: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
}

enum AchievementCatalog {
    static let all: [Achievement] = [
        Achievement(id: "first_drive", title: "İlk Sürüş", subtitle: "İlk sürüşünü kaydettin", icon: "flag.checkered"),
        Achievement(id: "distance_100", title: "100 km", subtitle: "Toplamda 100 km yol kat ettin", icon: "road.lanes"),
        Achievement(id: "distance_500", title: "500 km", subtitle: "Toplamda 500 km yol kat ettin", icon: "road.lanes"),
        Achievement(id: "distance_1000", title: "1000 km", subtitle: "Toplamda 1000 km yol kat ettin", icon: "road.lanes"),
        Achievement(id: "night_owl", title: "Gece Kuşu", subtitle: "Gece yarısı ile 05:00 arasında bir sürüş yaptın", icon: "moon.stars.fill"),
        Achievement(id: "smooth_operator", title: "Fren Ustası", subtitle: "En az 1 km'lik bir sürüşü hiç ani fren yapmadan tamamladın", icon: "hand.raised.fill"),
        Achievement(id: "century_drive", title: "Maraton", subtitle: "Tek bir sürüşte 50 km'yi geçtin", icon: "trophy.fill"),
        Achievement(id: "week_streak", title: "7 Gün Üst Üste", subtitle: "7 gün art arda sürüş yaptın", icon: "calendar"),
    ]
}
