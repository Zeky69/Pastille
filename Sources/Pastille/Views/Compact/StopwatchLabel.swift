import SwiftUI

/// Temps au centième, comme Horloge (« 0:05,23 »).
/// Dessiné par une couche Core Animation de taille fixe, mise à jour 30 fois par seconde :
/// rien ne repasse par SwiftUI ni par la mise en page de la pastille.
struct StopwatchLabel: NSViewRepresentable {
    let stopwatch: ClockStopwatch

    func makeNSView(context: Context) -> StopwatchTextView {
        StopwatchTextView()
    }

    func updateNSView(_ view: StopwatchTextView, context: Context) {
        view.stopwatch = stopwatch
    }
}

final class StopwatchTextView: NSView {
    var stopwatch: ClockStopwatch? {
        didSet {
            guard stopwatch != oldValue else { return }
            render()
            updateTicker()
        }
    }

    private let text = CATextLayer()
    private var ticker: Timer?
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        text.font = Self.font
        text.fontSize = Self.font.pointSize
        text.foregroundColor = NSColor.systemOrange.cgColor
        text.alignmentMode = .right
        text.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "opacity": NSNull()]
        layer?.addSublayer(text)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Hauteur d'une ligne ; la largeur vient de la pastille.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.font.ascender - Self.font.descender + 2)
    }

    override func layout() {
        super.layout()
        let height = intrinsicContentSize.height
        // Aligné à droite ; on laisse 8 pt de débord côté encoche pour ne jamais couper le texte.
        text.frame = CGRect(x: -8, y: (bounds.height - height) / 2, width: bounds.width + 8, height: height)
        text.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTicker()
    }

    /// Ne tourne que si le chronomètre tourne et que la vue est affichée.
    private func updateTicker() {
        let running = window != nil && stopwatch?.isPaused == false
        if running, ticker == nil {
            let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.render() }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        } else if !running {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func render() {
        guard let stopwatch else { return }
        text.opacity = stopwatch.isPaused ? 0.6 : 1
        text.string = Self.format(stopwatch.elapsed())
    }

    private static func format(_ seconds: Double) -> String {
        let total = Int(seconds * 100)
        let (hours, minutes, secs, hundredths) = (total / 360_000, total / 6000 % 60, total / 100 % 60, total % 100)
        return hours > 0
            ? String(format: "%d:%02d:%02d,%02d", hours, minutes, secs, hundredths)
            : String(format: "%d:%02d,%02d", minutes, secs, hundredths)
    }
}

// MARK: - Son / luminosité
