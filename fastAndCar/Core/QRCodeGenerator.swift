//
//  QRCodeGenerator.swift
//  fastAndCar
//
//  Renders a plain QR code image from a string (a CKShare.url, in
//  practice). CKShare URLs are universal links, so a scanned code needs no
//  custom in-app scanner — iOS's own Camera app already recognizes them and
//  routes straight into CrewShareAppDelegate.userDidAcceptCloudKitShareWith,
//  the same entry point Messages/Mail/copy-link already use.
//

import CoreImage.CIFilterBuiltins
import UIKit

enum QRCodeGenerator {
    static func image(from string: String, scale: CGFloat = 10) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
