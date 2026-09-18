//
//  CloudSharingSheet.swift
//  fastAndCar
//
//  Thin UIViewControllerRepresentable over UICloudSharingController — the
//  system's own invite UI (Messages/Mail/copy link, plus its own
//  read-only-vs-can-edit permission picker per participant), so Crew
//  invites look and behave like every other iOS share sheet instead of a
//  custom one this app would have to maintain.
//

import CloudKit
import SwiftUI

struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
}
