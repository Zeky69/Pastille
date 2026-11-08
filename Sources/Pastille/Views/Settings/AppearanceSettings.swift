import Combine
import ServiceManagement
import SwiftUI

struct AppearanceSettings: View {
    @AppStorage(Appearance.presetKey) private var preset = Appearance.Preset.classic.rawValue
    @AppStorage(Appearance.homeLayoutKey) private var layout = Appearance.HomeLayout.musicAndCalendar.rawValue
    @AppStorage(Appearance.calendarStyleKey) private var calendarStyle = Appearance.CalendarStyle.wheel.rawValue
    @AppStorage(Appearance.musicStyleKey) private var musicStyle = Appearance.MusicStyle.artwork.rawValue
    @AppStorage(Appearance.accentKey) private var accent = Appearance.AccentChoice.artwork.rawValue
    @AppStorage(Appearance.sizeKey) private var size = Appearance.PillSize.standard.rawValue
    @AppStorage(Appearance.materialKey) private var material = Appearance.PillMaterial.black.rawValue
    @AppStorage(Appearance.showWeatherKey) private var showWeather = true
    @AppStorage(Appearance.showBluetoothKey) private var showBluetooth = true
    @AppStorage(Appearance.showCaffeineKey) private var showCaffeine = true
    @AppStorage(Appearance.showScreenshotsTabKey) private var showScreenshotsTab = true
    @AppStorage(Appearance.showShelfTabKey) private var showShelfTab = true
    @AppStorage(Settings.showBatteryPercentKey) private var showBatteryPercent = true
    @AppStorage(Appearance.weatherUnitKey) private var weatherUnit = "celsius"

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
                Picker("Fond de la pastille", selection: custom($material)) {
                    ForEach(Appearance.PillMaterial.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
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
                if showWeather {
                    Picker("Unité", selection: $weatherUnit) {
                        Text("°C").tag("celsius")
                        Text("°F").tag("fahrenheit")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                Toggle("Appareils Bluetooth", isOn: custom($showBluetooth))
                Toggle("Tasse de café", isOn: custom($showCaffeine))
                Toggle("Pourcentage de batterie", isOn: custom($showBatteryPercent))
                Toggle("Onglet Captures d'écran", isOn: custom($showScreenshotsTab))
                Toggle("Onglet Étagère (glisser des fichiers sur l'encoche)", isOn: custom($showShelfTab))
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

/// Pastilles de couleur ; la première reprend la couleur de la pochette.
struct AccentPicker: View {
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
