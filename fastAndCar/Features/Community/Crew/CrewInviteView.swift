//
//  CrewInviteView.swift
//  fastAndCar
//
//  Faz 3 — shows the crew's CKShare invite as a scannable QR code first,
//  with the system share sheet (Messages/Mail/copy link — CloudSharingSheet)
//  one tap away for when the other person isn't standing right there. Both
//  are the exact same CKShare.url; the QR code is just a second way to hand
//  it over, not a separate invite mechanism, so there's nothing new to keep
//  in sync with the CloudKit side.
//
//  Still behind FeatureFlags.crewEnabled like the rest of Crew — code-
//  complete and ready, but only actually reachable (and end-to-end
//  testable, i.e. a real scan being accepted) once that's on.
//

import CloudKit
import SwiftUI

struct CrewInviteView: View {
    let crewName: String
    let share: CKShare
    let container: CKContainer

    @Environment(\.dismiss) private var dismiss
    @State private var showsSystemShare = false

    private var qrImage: UIImage? {
        guard let url = share.url else { return nil }
        return QRCodeGenerator.image(from: url.absoluteString)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    if let qrImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                            .padding(18)
                            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white))
                            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                    } else {
                        // The share hasn't been assigned a public URL yet
                        // (shouldn't happen here — presentInvite() only
                        // sets pendingShare once the CKShare is already
                        // saved) — falls back to the system share sheet
                        // only, no dead QR placeholder.
                        ProgressView().tint(AppColor.accent)
                    }

                    VStack(spacing: 6) {
                        Text(crewName)
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Katılmak için bu kodu okutsun")
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .multilineTextAlignment(.center)

                    Spacer()

                    Button {
                        showsSystemShare = true
                    } label: {
                        Label("Diğer Yollarla Paylaş", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.glass(.accent))
                }
                .padding(28)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsSystemShare) {
            CloudSharingSheet(share: share, container: container)
        }
    }
}
