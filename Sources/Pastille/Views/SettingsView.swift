import ServiceManagement
import SwiftUI

/// Réglages en trois onglets : Apparence (préréglages + personnalisation), Activités, Général.
/// Tout s'applique en direct à la pastille.
struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettings()
                .tabItem { Label("Apparence", systemImage: "paintbrush.fill") }
            ActivitySettings()
                .tabItem { Label("Activités", systemImage: "capsule.fill") }
            GeneralSettings()
                .tabItem { Label("Général", systemImage: "gearshape.fill") }
        }
        .frame(width: 580, height: 640)
    }
}

// MARK: - Apparence

private struct AppearanceSettings: View {
    @AppStorage(Appearance.presetKey) private var preset = Appearance.Preset.classic.rawValue
    @AppStorage(Appearance.homeLayoutKey) private var layout = Appearance.HomeLayout.musicAndCalendar.rawValue
    @AppStorage(Appearance.calendarStyleKey) private var calendarStyle = Appearance.CalendarStyle.wheel.rawValue
    @AppStorage(Appearance.musicStyleKey) private var musicStyle = Appearance.MusicStyle.artwork.rawValue
    @AppStorage(Appearance.accentKey) private var accent = Appearance.AccentChoice.artwork.rawValue
    @AppStorage(Appearance.sizeKey) private var size = Appearance.PillSize.standard.rawValue
    @AppStorage(Appearance.showWeatherKey) private var showWeather = true
    @AppStorage(Appearance.showBluetoothKey) private var showBluetooth = true
    @AppStorage(Appearance.showCaffeineKey) private var showCaffeine = true
    @AppStorage(Appearance.showScreenshotsTabKey) private var showScreenshotsTab = true
    @AppStorage(Settings.showBatteryPercentKey) private var showBatteryPercent = true

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    ForEach(Appearance.Preset.selectable) { item in
                        PresetCard(preset: item, isSelected: preset == item.rawValue) {
                            withAnimation(.snappy) { item.apply() }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                HStack {
                    Text("Préréglages")
                    Spacer()
                    if preset == Appearance.Preset.custom.rawValue {
                        Label("Perso", systemImage: "slider.horizontal.3")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Page d'accueil") {
                Picker("Contenu", selection: custom($layout)) {
                    ForEach(Appearance.HomeLayout.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                if layout != Appearance.HomeLayout.musicOnly.rawValue {
                    Picker("Calendrier", selection: custom($calendarStyle)) {
                        ForEach(Appearance.CalendarStyle.allCases) {
                            Label($0.label, systemImage: $0.symbol).tag($0.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if layout != Appearance.HomeLayout.calendarOnly.rawValue {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lecteur")
                        HStack(spacing: 8) {
                            ForEach(Appearance.MusicStyle.allCases) { style in
                                MusicStyleCard(style: style, isSelected: musicStyle == style.rawValue) {
                                    withAnimation(.snappy) { custom($musicStyle).wrappedValue = style.rawValue }
                                }
                            }
                        }
                        Text((Appearance.MusicStyle(rawValue: musicStyle) ?? .artwork).summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Style") {
                Picker("Taille ouverte", selection: custom($size)) {
                    ForEach(Appearance.PillSize.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Couleur d'accent") {
                    AccentPicker(selection: custom($accent))
                }
            }

            Section("En-tête") {
                Toggle("Météo", isOn: custom($showWeather))
                Toggle("Appareils Bluetooth", isOn: custom($showBluetooth))
                Toggle("Tasse de café", isOn: custom($showCaffeine))
                Toggle("Pourcentage de batterie", isOn: custom($showBatteryPercent))
                Toggle("Onglet Captures d'écran", isOn: custom($showScreenshotsTab))
            }
        }
        .formStyle(.grouped)
    }

    /// Toute modification à la main fait passer en préréglage « Perso ».
    private func custom<T: Equatable>(_ binding: Binding<T>) -> Binding<T> {
        Binding(
            get: { binding.wrappedValue },
            set: { value in
                guard value != binding.wrappedValue else { return }
                binding.wrappedValue = value
                Appearance.markCustom()
            }
        )
    }
}

/// Carte de préréglage : mini-aperçu de la pastille ouverte + nom.
private struct PresetCard: View {
    let preset: Appearance.Preset
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                PresetPreview(preset: preset)
                    .frame(height: 54)
                Text(preset.label)
                    .font(.callout.weight(.semibold))
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(preset.summary)
    }
}

/// Dessin schématique de chaque préréglage.
private struct PresetPreview: View {
    let preset: Appearance.Preset

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                .fill(.black)
            content
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 6)
        }
        .frame(width: preset == .minimal ? 92 : preset == .music ? 118 : 106)
    }

    private let block = Color.white.opacity(0.25)
    private let line = Color.white.opacity(0.18)

    @ViewBuilder
    private var content: some View {
        switch preset {
        case .classic, .custom:
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(Color.pink.opacity(0.7)).frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(line).frame(width: 26, height: 3)
                    Capsule().fill(Color.pink.opacity(0.7)).frame(width: 30, height: 2)
                }
                Spacer(minLength: 0)
                VStack(spacing: 3) {
                    HStack(spacing: 2) { ForEach(0..<4, id: \.self) { _ in Circle().fill(line).frame(width: 4, height: 4) } }
                    Capsule().fill(line).frame(width: 22, height: 3)
                }
            }
        case .minimal:
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(block).frame(width: 12, height: 12)
                Capsule().fill(line).frame(width: 30, height: 3)
                Spacer(minLength: 0)
                Image(systemName: "play.fill").font(.system(size: 6)).foregroundStyle(.white.opacity(0.6))
            }
        case .music:
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.85)).frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(.white.opacity(0.5)).frame(width: 34, height: 3)
                    Capsule().fill(Color.orange.opacity(0.9)).frame(width: 46, height: 2)
                }
                Spacer(minLength: 0)
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [.orange.opacity(0.45), .purple.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
            )
        case .agenda:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    HStack(spacing: 3) {
                        Capsule().fill(index == 0 ? Color.blue : line).frame(width: 2, height: 7)
                        Capsule().fill(line).frame(width: CGFloat(40 - index * 8), height: 3)
                        Spacer(minLength: 0)
                        Capsule().fill(line).frame(width: 10, height: 3)
                    }
                }
            }
        }
    }
}

/// Carte d'un style de lecteur, avec son mini-aperçu.
private struct MusicStyleCard: View {
    let style: Appearance.MusicStyle
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                MusicStylePreview(style: style)
                    .frame(width: 84, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(style.label).font(.caption.weight(.semibold))
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(hovering ? 0.08 : 0.04)))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct MusicStylePreview: View {
    let style: Appearance.MusicStyle

    private let art = LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
    private let line = Color.white.opacity(0.3)

    var body: some View {
        ZStack {
            Color.black
            switch style {
            case .artwork:
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(art).frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule().fill(line).frame(width: 30, height: 3)
                        Capsule().fill(Color.pink).frame(width: 40, height: 2)
                        HStack(spacing: 4) { ForEach(0..<3, id: \.self) { _ in Circle().fill(line).frame(width: 4, height: 4) } }
                    }
                }
            case .poster:
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 4).fill(art).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule().fill(.white.opacity(0.7)).frame(width: 30, height: 5)
                        Capsule().fill(Color.pink).frame(width: 22, height: 3)
                        Spacer().frame(height: 6)
                        Capsule().fill(line).frame(width: 34, height: 2)
                    }
                }
            case .compact:
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(art).frame(width: 12, height: 12)
                    Capsule().fill(line).frame(width: 30, height: 3)
                    Spacer(minLength: 0)
                    Image(systemName: "play.fill").font(.system(size: 6)).foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .frame(height: 20)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .padding(.horizontal, 6)
            case .immersive:
                ZStack {
                    LinearGradient(colors: [.pink.opacity(0.8), .orange.opacity(0.6), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .blur(radius: 6)
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3).fill(art).frame(width: 16, height: 16).shadow(radius: 2)
                            Capsule().fill(.white.opacity(0.8)).frame(width: 30, height: 3)
                        }
                        HStack(spacing: 7) { ForEach(0..<3, id: \.self) { i in Circle().fill(.white.opacity(0.85)).frame(width: i == 1 ? 6 : 4, height: i == 1 ? 6 : 4) } }
                    }
                }
            case .vinyl:
                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(Color(white: 0.12))
                        Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5).padding(4)
                        Circle().fill(art).padding(10)
                        Circle().fill(Color(white: 0.12)).frame(width: 3, height: 3)
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule().fill(line).frame(width: 28, height: 3)
                        Capsule().fill(Color.pink).frame(width: 22, height: 2)
                    }
                }
            }
        }
    }
}

/// Pastilles de couleur ; la première reprend la couleur de la pochette.
private struct AccentPicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Appearance.AccentChoice.allCases) { choice in
                Button { selection = choice.rawValue } label: {
                    ZStack {
                        if let color = choice.color {
                            Circle().fill(color)
                        } else {
                            Circle().fill(AngularGradient(colors: [.pink, .orange, .yellow, .green, .blue, .purple, .pink], center: .center))
                        }
                        if selection == choice.rawValue {
                            Circle().strokeBorder(Color.primary, lineWidth: 2).padding(-3)
                        }
                    }
                    .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(choice.label)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Activités

private struct ActivitySettings: View {
    @AppStorage(Settings.musicLiveActivityKey) private var music = true
    @AppStorage(Appearance.clockActivityKey) private var clock = true
    @AppStorage(Appearance.downloadActivityKey) private var download = true
    @AppStorage(Appearance.codeActivityKey) private var code = true
    @AppStorage(Appearance.hudActivityKey) private var hud = true
    @AppStorage(Appearance.batteryAlertKey) private var battery = true

    var body: some View {
        Form {
            Section {
                row("music.note", .pink, "Musique en cours", "Pochette et spectre de part et d'autre de l'encoche.", $music)
                row("timer", .orange, "Minuteur et chronomètre", "Ceux de l'app Horloge, en direct.", $clock)
                row("arrow.down.circle.fill", .blue, "Téléchargements", "Anneau de progression puis coche verte.", $download)
                row("key.fill", .green, "Codes de vérification", "Reçus par SMS, iMessage ou Mail.", $code)
                row("speaker.wave.2.fill", .gray, "Volume et luminosité", "Remplace l'indicateur d'Apple (désactivé : celui d'Apple revient).", $hud)
                row("battery.25", .red, "Batterie faible", "Alerte à 20 %, 10 % et 5 %.", $battery)
            } header: {
                Text("Ce qui peut s'afficher dans la pastille fermée")
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ symbol: String, _ color: Color, _ title: String, _ detail: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Général

private struct GeneralSettings: View {
    @AppStorage(Settings.openOnHoverKey) private var openOnHover = true
    @AppStorage(Settings.hoverDelayKey) private var hoverDelay = 0.15
    @AppStorage(Settings.hapticsKey) private var haptics = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Comportement") {
                Toggle("Ouvrir au survol", isOn: $openOnHover)
                if openOnHover {
                    Slider(value: $hoverDelay, in: 0...0.6, step: 0.05) {
                        Text("Délai : \(Int(hoverDelay * 1000)) ms")
                    }
                }
                Toggle("Retour haptique", isOn: $haptics)
                Toggle("Lancer à l'ouverture de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
            }
        }
        .formStyle(.grouped)
    }
}
