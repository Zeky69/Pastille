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
        case .newTrack:
            Color.clear
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
        case .newTrack:
            Color.clear
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

// MARK: - Amorce des animations
