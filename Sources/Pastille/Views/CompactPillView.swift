import SwiftUI

/// Pastille compacte : vide, ou flanquée d'une activité (musique, charge, batterie faible, minuteur, chronomètre, téléchargement, café, code reçu, son, luminosité).
struct CompactPillView: View {
    @ObservedObject var viewModel: PillViewModel
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var battery = BatteryManager.shared
    @ObservedObject private var timers = TimerManager.shared
    @ObservedObject private var hud = HUDManager.shared
    @ObservedObject private var downloads = DownloadManager.shared
    @ObservedObject private var caffeine = CaffeineManager.shared
    @ObservedObject private var codes = VerificationCodeManager.shared
    @ObservedObject private var bluetooth = BluetoothManager.shared
    @AppStorage(Appearance.accentKey) private var accentRaw = Appearance.AccentChoice.artwork.rawValue
    /// Activité dessinée. Quand elle se termine, on garde son contenu le temps que les côtés
    /// se replient : il glisse alors sous l'encoche au lieu de s'effacer d'un coup.
    @State private var shown: LiveActivity = .none

    private var h: CGFloat { viewModel.cutoutSize.height }

    private var lowBatteryThreshold: Int? {
        if case .lowBattery(let threshold) = viewModel.moment { threshold } else { nil }
    }

    private var caffeineOn: Bool {
        if case .caffeine(let isOn) = viewModel.moment { isOn } else { caffeine.isActive }
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: viewModel.sideWidth, height: h)
            Spacer(minLength: 0)
            trailing
                .frame(width: viewModel.sideWidth, height: h)
        }
        .opacity(shown == .none ? 0 : 1)
        .onChange(of: viewModel.liveActivity, initial: true) { _, activity in
            guard activity == .none else {
                shown = activity
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                if viewModel.liveActivity == .none { shown = .none }
            }
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch shown {
        case .music:
            ArtworkView(image: music.artwork, cornerRadius: 5)
                .frame(width: h - 10, height: h - 10)
        case .charging:
            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.green)
        case .unplugged:
            UnpluggedIcon()
        case .charged:
            Image(systemName: "battery.100percent.bolt")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.green)
                .modifier(PopIn())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
        case .deviceConnected:
            if case .deviceConnected(let snapshot) = viewModel.moment {
                let device = bluetooth.current(snapshot)
                HStack(spacing: 6) {
                    Image(systemName: device.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .modifier(PopIn())
                    Text(device.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
            }
        case .lowBattery:
            BatteryIcon(level: battery.level, isCharging: false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
        case .timer:
            if let timer = timers.timer {
                TimerRing(timer: timer)
                    .frame(width: 16, height: 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
            }
        case .download:
            Image(systemName: downloads.state == .finished ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(downloads.state == .finished ? .green : .blue)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: downloads.state != .finished)
        case .code:
            Image(systemName: codes.copied ? "checkmark.circle.fill" : "key.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
        case .caffeine:
            Image(systemName: caffeineOn ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(caffeineOn ? Color.orange : Color.white.opacity(0.6))
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
        case .stopwatch:
            Image(systemName: "stopwatch.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
                .opacity(timers.stopwatch?.isPaused == true ? 0.6 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
        case .hud:
            if let value = hud.current {
                Image(systemName: value.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 11)
            }
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch shown {
        case .music:
            AudioVisualizer(isPlaying: music.isPlaying, color: Appearance.AccentChoice.resolve(accentRaw, artwork: music.accentColor))
                .frame(width: 18, height: 12)
        case .charging:
            BatteryIcon(level: battery.level, isCharging: true)
        case .unplugged:
            BatteryIcon(level: battery.level, isCharging: false)
        case .charged:
            Text("Chargé")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
        case .deviceConnected:
            if case .deviceConnected(let snapshot) = viewModel.moment {
                ConnectedRing(level: bluetooth.current(snapshot).level)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
            }
        case .lowBattery:
            Text("\(lowBatteryThreshold ?? battery.level)%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.red)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
        case .timer:
            if let timer = timers.timer {
                TimerLabel(timer: timer)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
            }
        case .download:
            DownloadRing(state: downloads.state)
                .frame(width: 16, height: 16)
                .help(downloads.state == .finished ? "Ouvrir le fichier (⌥ : le montrer dans le Finder)" : "")
        case .code:
            if let code = codes.current {
                Text(code.code)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
            }
        case .caffeine:
            Text(caffeineOn ? "Éveillé" : "Veille")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(caffeineOn ? Color.orange : Color.white.opacity(0.6))
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
        case .stopwatch:
            if let stopwatch = timers.stopwatch {
                StopwatchLabel(stopwatch: stopwatch)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.trailing, 12)
            }
        case .hud:
            if let value = hud.current {
                LevelBar(level: value.muted ? 0 : value.level)
                    .frame(width: 44, height: 5)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 11)
            }
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Appareil connecté, Mac chargé

/// Apparition avec un petit rebond, comme sur iPhone.
private struct PopIn: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.3)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.spring(duration: 0.5, bounce: 0.5).delay(0.1)) { shown = true }
            }
    }
}

/// Anneau de batterie qui se remplit à l'apparition, avec le pourcentage à côté.
/// Niveau inconnu (-1) : « Connecté », le temps que la batterie arrive.
private struct ConnectedRing: View {
    let level: Int
    @State private var filled = false

    private var color: Color { level <= 20 ? .red : .green }

    var body: some View {
        if level < 0 {
            Text("Connecté")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize()
                .transition(.opacity)
        } else {
            HStack(spacing: 5) {
                Text("\(level)%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .fixedSize()
                ZStack {
                    Circle().stroke(color.opacity(0.25), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: filled ? CGFloat(level) / 100 : 0)
                        .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 15, height: 15)
            }
            .transition(.opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8).delay(0.15)) { filled = true }
            }
        }
    }
}

// MARK: - Débranchement

/// Éclair qui s'éteint : vert au départ, il se barre et devient gris.
private struct UnpluggedIcon: View {
    @State private var off = false

    var body: some View {
        Image(systemName: off ? "bolt.slash.fill" : "bolt.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(off ? Color.white.opacity(0.7) : .green)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: off)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.spring(duration: 0.4, bounce: 0.3)) { off = true }
                }
            }
    }
}

// MARK: - Minuteur

/// Anneau orange qui se vide au fil du temps.
private struct TimerRing: View {
    let timer: ClockTimer

    var body: some View {
        // Une image par seconde suffit : l'anneau bouge de moins de 2 % par seconde dès 1 min.
        TimelineView(.periodic(from: .now, by: timer.duration < 60 ? 0.25 : 1)) { context in
            ZStack {
                Circle().stroke(Color.orange.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: timer.progress(at: context.date))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

private struct TimerLabel: View {
    let timer: ClockTimer

    var body: some View {
        // Calé juste après chaque changement de seconde, sans animation, comme Horloge.
        TimelineView(.periodic(from: tickStart, by: 1)) { context in
            Text(format(timer.remaining(at: context.date)))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.orange)
                .opacity(timer.isPaused ? 0.6 : 1)
                .transaction { $0.animation = nil }
        }
    }

    /// Un changement de seconde passé (à chaque « ,5 » restant), plus 20 ms pour tomber sûrement après.
    private var tickStart: Date {
        guard let fireDate = timer.fireDate else { return .now }
        let remaining = fireDate.timeIntervalSinceNow
        return fireDate.addingTimeInterval(-((remaining - 0.5).rounded(.up) + 0.5) + 0.02)
    }

    private func format(_ seconds: Double) -> String {
        // Horloge arrondit à la seconde la plus proche (850,88 s s'affiche 14:11).
        let s = Int(seconds.rounded())
        let (hours, minutes, secs) = (s / 3600, (s % 3600) / 60, s % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Téléchargement

/// Anneau de progression ; s'il n'y a pas de pourcentage, un arc qui tourne.
private struct DownloadRing: View {
    let state: DownloadManager.State
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.blue.opacity(0.25), lineWidth: 2.5)
            switch state {
            case .downloading(let fraction?):
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            case .downloading(nil):
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
            case .finished:
                Circle().stroke(Color.green, lineWidth: 2.5)
            case .idle:
                EmptyView()
            }
        }
    }
}

// MARK: - Chronomètre

/// Temps au centième, comme Horloge (« 0:05,23 »).
/// Dessiné par une couche Core Animation de taille fixe, mise à jour 30 fois par seconde :
/// rien ne repasse par SwiftUI ni par la mise en page de la pastille.
private struct StopwatchLabel: NSViewRepresentable {
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

private struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule()
                    .fill(.white)
                    .frame(width: geo.size.width * CGFloat(min(max(level, 0), 1)))
            }
        }
        .animation(.spring(duration: 0.25, bounce: 0.1), value: level)
    }
}

extension HUDValue {
    var symbol: String {
        switch kind {
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            // Casque ou AirPods : leur icône (la barre montre le niveau, vide si coupé).
            switch output {
            case .headphones: return "headphones"
            case .airpods: return "airpods"
            case .airpodsPro: return "airpodspro"
            case .airpodsMax: return "airpodsmax"
            case .speaker: break
            }
            if muted || level == 0 { return "speaker.slash.fill" }
            if level < 0.33 { return "speaker.wave.1.fill" }
            if level < 0.66 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }
}
