//
//  OnboardingView.swift
//  fastAndCar
//
//  Single-screen onboarding: a self-drawing route line is the entire wow
//  moment, followed by one glass button. No multi-page slog.
//

import SwiftUI

struct OnboardingView: View {
    @State private var viewModel: OnboardingViewModel
    @State private var lineProgress: CGFloat = 0
    @State private var showsText = false

    init(locationManager: LocationManager, onFinished: @escaping () -> Void) {
        _viewModel = State(initialValue: OnboardingViewModel(locationManager: locationManager, onFinished: onFinished))
    }

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
                .frame(height: 200)
                .padding(.horizontal, 40)

                VStack(spacing: 12) {
                    Text("Her sürüş bir rota.")
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)

                    Text("fastAndCar yolculuğunu kaydeder, pist haritası gibi çizer.")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 44)
                }
                .padding(.top, 32)
                .opacity(showsText ? 1 : 0)
                .offset(y: showsText ? 0 : 8)

                Spacer()
                Spacer()

                Button("Konumu Etkinleştir") {
                    viewModel.requestPermission()
                }
                .buttonStyle(.glass(.accent))
                .opacity(showsText ? 1 : 0)
                .padding(.bottom, 56)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6)) {
                lineProgress = 1
            }
            withAnimation(.easeOut(duration: 0.5).delay(1.0)) {
                showsText = true
            }
            // Permission may already be determined (e.g. granted in a prior
            // install) — CoreLocation won't fire a fresh delegate callback in
            // that case, so onChange alone would never advance past this screen.
            viewModel.handleAuthorizationChange(viewModel.authorizationStatus)
        }
        .onChange(of: viewModel.authorizationStatus) { _, newValue in
            viewModel.handleAuthorizationChange(newValue)
        }
    }
}

#Preview {
    OnboardingView(locationManager: LocationManager(), onFinished: {})
}
