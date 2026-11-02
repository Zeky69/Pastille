import SwiftUI

/// Faux spectre animé, comme sur iOS. Les barres sont des couches Core Animation qui bougent toutes
/// seules (le système les anime) : la vue SwiftUI n'est jamais recalculée pendant la lecture.
struct AudioVisualizer: NSViewRepresentable {
    let isPlaying: Bool
    let color: Color

    func makeNSView(context: Context) -> VisualizerView { VisualizerView() }

    func updateNSView(_ view: VisualizerView, context: Context) {
        view.update(isPlaying: isPlaying, color: NSColor(color))
    }
}

final class VisualizerView: NSView {
    private let bars = (0..<4).map { _ in CALayer() }
    private var isPlaying = false

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        bars.forEach { layer?.addSublayer($0) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let spacing: CGFloat = 2
        let width = (bounds.width - spacing * CGFloat(bars.count - 1)) / CGFloat(bars.count)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(index) * (width + spacing) + width / 2, y: bounds.midY)
            bar.cornerRadius = width / 2
        }
        restartAnimations()
    }

    func update(isPlaying: Bool, color: NSColor) {
        bars.forEach { $0.backgroundColor = color.cgColor }
        guard isPlaying != self.isPlaying else { return }
        self.isPlaying = isPlaying
        restartAnimations()
    }

    /// Chaque barre monte et descend à son propre rythme ; à l'arrêt, elles se posent à 3 pt.
    private func restartAnimations() {
        let rest = bounds.height > 0 ? 3 / bounds.height : 0.25
        for (index, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            guard isPlaying else {
                bar.transform = CATransform3DMakeScale(1, rest, 1)
                continue
            }
            bar.transform = CATransform3DIdentity
            let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
            animation.values = [rest, 1, 0.45, 0.85, rest + 0.1, 0.7, rest]
            animation.duration = [0.9, 1.15, 0.8, 1.05][index]
            animation.timeOffset = Double(index) * 0.37
            animation.repeatCount = .infinity
            animation.calculationMode = .cubic
            bar.add(animation, forKey: "dance")
        }
    }
}
