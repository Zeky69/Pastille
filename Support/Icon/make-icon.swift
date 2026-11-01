// Dessine l'icône de Pastille et produit Support/AppIcon.icns.
// Lancement : swift Support/Icon/make-icon.swift (depuis la racine du projet).
import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let s = rect.width
        // Carré arrondi façon macOS, avec la marge standard (~10 %).
        let inset = s * 0.1
        let tile = rect.insetBy(dx: inset, dy: inset)
        let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)

        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = s * 0.025
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
        shadow.set()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.95, alpha: 1),
            NSColor(calibratedRed: 0.93, green: 0.36, blue: 0.62, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.32, alpha: 1),
        ])!.draw(in: tilePath, angle: -60)
        NSGraphicsContext.current?.restoreGraphicsState()

        // Écran : la pastille posée en haut, comme sous l'encoche.
        let pillWidth = tile.width * 0.62
        let pillHeight = tile.width * 0.2
        let pill = NSRect(x: tile.midX - pillWidth / 2, y: tile.maxY - tile.height * 0.32 - pillHeight / 2,
                          width: pillWidth, height: pillHeight)
        let pillPath = NSBezierPath(roundedRect: pill, xRadius: pillHeight / 2, yRadius: pillHeight / 2)
        NSGraphicsContext.current?.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        glow.shadowBlurRadius = s * 0.03
        glow.shadowOffset = NSSize(width: 0, height: -s * 0.015)
        glow.set()
        NSColor.black.setFill()
        pillPath.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        // Reflet discret sur le haut de la pastille.
        NSGraphicsContext.current?.saveGraphicsState()
        pillPath.addClip()
        let shine = NSRect(x: pill.minX, y: pill.midY, width: pill.width, height: pill.height / 2)
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
            .draw(in: shine, angle: -90)
        NSGraphicsContext.current?.restoreGraphicsState()

        // Petit point vert d'activité et barres de musique dans la pastille.
        let dot = pillHeight * 0.34
        NSColor(calibratedRed: 0.20, green: 0.84, blue: 0.42, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: pill.minX + pillHeight * 0.38, y: pill.midY - dot / 2, width: dot, height: dot)).fill()
        let barWidth = pillHeight * 0.1
        for (index, height) in [0.38, 0.62, 0.3, 0.5].enumerated() {
            let h = pillHeight * height
            let x = pill.maxX - pillHeight * 0.95 + CGFloat(index) * barWidth * 1.9
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: pill.midY - h / 2, width: barWidth, height: h),
                         xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
        return true
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appending(path: "build/Pastille.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let image = drawIcon(size: CGFloat(pixels))
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appending(path: name))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appending(path: "Support/AppIcon.icns").path]
try! process.run()
process.waitUntilExit()
print(process.terminationStatus == 0 ? "✅ Support/AppIcon.icns" : "❌ iconutil")
