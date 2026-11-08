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
    /// Morceau annoncé sous l'encoche (gardé pendant le repli).
    @State private var announcedTrack: Track?
    @State private var announcedArtwork: NSImage?
    @State private var announcedVisible = false
    @ObservedObject private var recorder = ScreenRecordingManager.shared
    /// La pochette et le spectre glissent d'une place à l'autre (en haut ↔ sous l'encoche).
    @Namespace private var morph

    private var h: CGFloat { viewModel.cutoutSize.height }

    private var lowBatteryThreshold: Int? {
        if case .lowBattery(let threshold) = viewModel.moment { threshold } else { nil }
    }

    private var caffeineOn: Bool {
        if case .caffeine(let isOn) = viewModel.moment { isOn } else { caffeine.isActive }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading
                    .frame(width: viewModel.sideWidth, height: h)
                Spacer(minLength: 0)
                trailing
                    .frame(width: viewModel.sideWidth, height: h)
            }
            below
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .opacity(shown == .none ? 0 : 1)
        // `initial` : si la pastille fermée réapparaît pendant une annonce, elle en reprend le contenu.
        .onChange(of: viewModel.moment, initial: true) { _, moment in
            if case .newTrack(let track, let artwork) = moment {
                // Même ressort que la pastille : la pochette et le spectre descendent sous l'encoche.
                withAnimation(PillAnimation.activity) {
                    announcedTrack = track
                    announcedArtwork = artwork
                }
                withAnimation(.easeOut(duration: 0.25).delay(0.15)) { announcedVisible = true }
            } else if announcedTrack != nil {
                // Et remontent à leur place pendant que la pastille se replie ; le texte s'efface.
                withAnimation(.easeOut(duration: 0.12)) { announcedVisible = false }
                withAnimation(PillAnimation.activity) { announcedTrack = nil }
            }
        }
        .onChange(of: viewModel.liveActivity, initial: true) { _, activity in
            guard activity == .none else {
                withAnimation(PillAnimation.activity) { shown = activity }
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
                .matchedGeometryEffect(id: "artwork", in: morph)
                .frame(width: h - 10, height: h - 10)
        case .charging:
            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.green)
        case .unplugged:
            UnpluggedIcon()
        case .timerDone:
            TimerDoneRing()
                .frame(width: 15, height: 15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
        case .newTrack, .screenshot:
            Color.clear
        case .recording:
            RecordingDot()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 13)
        case .focus:
            if case .focus(let mode, let isOn) = viewModel.moment {
                Image(systemName: mode.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? mode.color : Color.white.opacity(0.5))
                    .modifier(PopIn())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
            }
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
                // Pas de pulsation : un téléchargement peut durer des heures, et l'effet coûtait ~18 % de CPU.
        case .code:
            Image(systemName: codes.copied ? "checkmark.circle.fill" : "key.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
        case .update:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.blue)
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

    /// Sous l'encoche (pastille un peu plus haute) : titre et artiste du nouveau morceau, en entier.
    /// Le morceau s'efface en fondu dès que la pastille commence à remonter (rapide, pour ne jamais
    /// laisser une pastille étirée et vide, ni du texte qui dépasse).
    @ViewBuilder
    private var below: some View {
        if let track = announcedTrack {
            HStack(spacing: 9) {
                // Pochette en direct : macOS l'envoie souvent juste après le titre.
                ArtworkView(image: music.track == track ? (music.artwork ?? announcedArtwork) : announcedArtwork,
                            cornerRadius: 6)
                    .matchedGeometryEffect(id: "artwork", in: morph)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(track.artist)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                .truncationMode(.tail)
                // Seul le texte apparaît et disparaît en fondu ; pochette et spectre se déplacent.
                .opacity(announcedVisible ? 1 : 0)
                AudioVisualizer(isPlaying: music.isPlaying, color: Appearance.AccentChoice.resolve(accentRaw, artwork: music.accentColor))
                    .matchedGeometryEffect(id: "visualizer", in: morph)
                    .frame(width: 18, height: 12)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .padding(.top, 1)
        }
        // La pastille s'est élargie puis descend : la capture sort de l'encoche en grandissant,
        // et y remonte en rapetissant avant que la pastille se resserre.
        if viewModel.screenshotDropped, case .screenshot(let shot, _) = viewModel.moment {
            ScreenshotPreview(shot: shot, size: viewModel.screenshotPreviewSize, copied: Settings.screenshotAutoCopy)
                .id(shot.url)
                .padding(.top, 5)
                .frame(maxWidth: .infinity)
                // La forme de la pastille la découvre au fur et à mesure qu'elle descend ; elle-même ne fait
                // que se déplier un peu, sans apparaître d'un coup.
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.88, anchor: .top)
                        .combined(with: .opacity.animation(.easeOut(duration: 0.6))),
                    removal: .scale(scale: 0.88, anchor: .top)
                        .combined(with: .opacity.animation(.easeIn(duration: 0.45)))
                ))
        }
    }

    /// « 0:07 », « 12:34 », « 1:02:03 ».
    static func elapsed(since start: Date, at now: Date) -> String {
        let total = max(Int(now.timeIntervalSince(start)), 0)
        let (h, m, sec) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    @ViewBuilder
    private var trailing: some View {
        switch shown {
        case .music:
            AudioVisualizer(isPlaying: music.isPlaying, color: Appearance.AccentChoice.resolve(accentRaw, artwork: music.accentColor))
                .matchedGeometryEffect(id: "visualizer", in: morph)
                .frame(width: 18, height: 12)
                .modifier(FirstAnimationWarmUp())
        case .charging:
            BatteryIcon(level: battery.level, isCharging: true)
        case .unplugged:
            BatteryIcon(level: battery.level, isCharging: false)
        case .timerDone:
            Text("Terminé")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
        case .newTrack, .screenshot:
            Color.clear
        case .recording:
            if let start = recorder.startedAt {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    Text(Self.elapsed(since: start, at: context.date))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.red)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
            }
        case .focus:
            if case .focus(let mode, let isOn) = viewModel.moment {
                Text(isOn ? mode.name : "Désactivé")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? mode.color : Color.white.opacity(0.5))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
            }
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
            if case .downloading(nil) = downloads.state, let measure = downloads.measure {
                // Pas de pourcentage connu : le total déjà reçu, court (la vitesse, pastille ouverte).
                Text(measure.total)
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
            } else {
                DownloadRing(state: downloads.state)
                    .frame(width: 16, height: 16)
                    .help(downloads.state == .finished ? "Ouvrir le fichier (⌥ : le montrer dans le Finder)" : "")
            }
        case .code:
            if let code = codes.current {
                Text(code.code)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
            }
        case .update:
            if case let .update(version) = viewModel.moment {
                Text(version)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.blue)
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

/// Capture qui vient d'être prise : elle sort de l'encoche avec un flash blanc, comme un déclencheur,
/// puis « Copiée » apparaît dans le coin quand elle est déjà dans le presse-papiers.
/// Un clic ouvre l'outil Annoter d'Apple ; au survol, des boutons Partager, Finder et Corbeille.
/// On peut aussi la glisser directement dans une autre app.
private struct ScreenshotPreview: View {
    let shot: Screenshot
    let size: CGSize
    let copied: Bool
    @ObservedObject private var manager = ScreenshotManager.shared
    @State private var flash = 0.6
    @State private var badge = false
    @State private var hovering = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    var body: some View {
        let thumbnail = manager.thumbnails[shot.url]
        ZStack {
            shape.fill(.white.opacity(0.08))
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            }
            Color.white.opacity(flash)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.stroke(.white.opacity(hovering ? 0.35 : 0.16), lineWidth: 1))
        .scaleEffect(hovering ? 1.02 : 1)
        .contentShape(shape)
        .onTapGesture { manager.markup(shot) }
        .onDrag { NSItemProvider(contentsOf: shot.url) ?? NSItemProvider() }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                PreviewButton(symbol: "pencil.tip.crop.circle", help: "Annoter") { manager.markup(shot) }
                ShareLink(item: shot.url) {
                    PreviewButtonLabel(symbol: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .help("Partager")
                PreviewButton(symbol: "folder", help: "Afficher dans le Finder") { manager.reveal(shot) }
                PreviewButton(symbol: "trash", help: "Mettre à la corbeille") { manager.delete(shot) }
            }
            .padding(7)
            .opacity(hovering ? 1 : 0)
            .scaleEffect(hovering ? 1 : 0.85, anchor: .topTrailing)
        }
        .overlay(alignment: .bottomTrailing) {
            if copied {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 6.5, weight: .heavy))
                    Text("Copiée")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.55)))
                .background(Capsule().fill(.ultraThinMaterial))
                .padding(5)
                .scaleEffect(badge ? 1 : 0.6, anchor: .bottomTrailing)
                .opacity(badge && !hovering ? 1 : 0)
            }
        }
        .animation(.easeOut(duration: 0.2), value: thumbnail != nil)
        .onHover { inside in
            withAnimation(.spring(duration: 0.25, bounce: 0.3)) { hovering = inside }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) { flash = 0 }
            withAnimation(.spring(duration: 0.5, bounce: 0.4).delay(1.0)) { badge = true }
        }
    }
}

private struct PreviewButtonLabel: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(.black.opacity(0.6)))
            .background(Circle().fill(.ultraThinMaterial))
            .contentShape(Circle())
    }
}

private struct PreviewButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { PreviewButtonLabel(symbol: symbol) }
            .buttonStyle(.plain)
            .help(help)
    }
}

/// Point rouge qui respire pendant un enregistrement d'écran. Effet de symbole (animé par le système) :
/// une animation SwiftUI en boucle coûterait du processeur pendant tout l'enregistrement.
struct RecordingDot: View {
    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 9))
            .foregroundStyle(.red)
            .symbolEffect(.pulse, options: .repeating)
    }
}

// MARK: - Amorce des animations
