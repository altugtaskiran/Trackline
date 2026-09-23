//
//  SplashView.swift
//  fastAndCar
//
//  A brief branded intro shown on every launch (not just first-run
//  onboarding): the same self-drawing F1-style route line, the app name,
//  and a small developer credit pinned to the bottom.
//

import SwiftUI

struct SplashView: View {
    @State private var lineProgress: CGFloat = 0
    @State private var showsText = false

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                GeometryReader { proxy in
                    ZStack {
                        RouteMotifShape()
                            .trim(from: 0, to: lineProgress)
                            .stroke(
                                LinearGradient(
                                    colors: AppColor.heatmapStops.map(\.color),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                            )
                            .shadow(color: AppColor.accent.opacity(0.45), radius: 14)

                        Circle()
                            .fill(AppColor.routeStart)
                            .frame(width: 12, height: 12)
                            .shadow(color: AppColor.routeStart, radius: 8)
                            .position(
                                x: proxy.size.width * RouteMotifShape.startPointUnit.x,
                                y: proxy.size.height * RouteMotifShape.startPointUnit.y
                            )
                            .opacity(lineProgress > 0.02 ? 1 : 0)

                        Circle()
                            .fill(AppColor.routeEnd)
                            .frame(width: 12, height: 12)
                            .shadow(color: AppColor.routeEnd, radius: 8)
                            .position(
                                x: proxy.size.width * RouteMotifShape.endPointUnit.x,
                                y: proxy.size.height * RouteMotifShape.endPointUnit.y
                            )
                            .opacity(lineProgress > 0.97 ? 1 : 0)
                    }
                }
                .frame(height: 150)
                .padding(.horizontal, 56)

                Text("Trackline: Drive Tracker")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.top, 20)
                    .opacity(showsText ? 1 : 0)
                    .offset(y: showsText ? 0 : 6)

                Spacer()

                VStack(spacing: 4) {
                    Text("GELİŞTİRİCİ")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(AppColor.textTertiary)
                    Text("Altuğ Taşkıran")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .opacity(showsText ? 1 : 0)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.1)) {
                lineProgress = 1
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.7)) {
                showsText = true
            }
        }
    }
}
