import AppKit
import CoreImage
import Combine
import SwiftUI

extension NSImage {
    /// Version très floue et plus saturée, réduite à 64 px : agrandie, elle reste lisse, et son calcul
    /// ne coûte presque rien (une fois par pochette).
    func blurredBackground() -> NSImage? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cg)
        let scale = 64 / max(input.extent.width, input.extent.height)
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small.clampedToExtent()
            .applyingGaussianBlur(sigma: 5)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.4])
            .cropped(to: small.extent)
        guard let output = CIContext().createCGImage(blurred, from: blurred.extent) else { return nil }
        return NSImage(cgImage: output, size: NSSize(width: output.width, height: output.height))
    }

    /// Couleur moyenne (sert d'accent pour le visualiseur et la barre de progression).
    var averageColor: NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let color = NSColor(
            red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255, alpha: 1
        )
        // On éclaircit les couleurs trop sombres pour qu'elles restent visibles sur fond noir.
        return color.brightnessComponent < 0.5
            ? NSColor(hue: color.hueComponent, saturation: color.saturationComponent, brightness: 0.75, alpha: 1)
            : color
    }
}
