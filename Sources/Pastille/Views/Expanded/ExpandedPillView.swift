import SwiftUI

struct ExpandedPillView: View {
    @ObservedObject var viewModel: PillViewModel
    var onOpenSettings: () -> Void
    @AppStorage(Appearance.homeLayoutKey) private var layoutRaw = Appearance.HomeLayout.musicAndCalendar.rawValue
    @AppStorage(Appearance.showScreenshotsTabKey) private var showScreenshotsTab = true
    @AppStorage(Appearance.showShelfTabKey) private var showShelfTab = true
    @AppStorage(Appearance.musicStyleKey) private var musicStyleRaw = Appearance.MusicStyle.artwork.rawValue
    @AppStorage(Appearance.showBluetoothKey) private var showBluetooth = true
    @AppStorage(Appearance.showCaffeineKey) private var showCaffeine = true

    private var tabs: [PillTab] { PillViewModel.tabs(screenshots: showScreenshotsTab, shelf: showShelfTab) }

    /// Lecteur compact seul : la pastille est plus étroite, l'en-tête se resserre.
    private var compact: Bool {
        layoutRaw == Appearance.HomeLayout.musicOnly.rawValue && musicStyleRaw == Appearance.MusicStyle.compact.rawValue
    }

    /// La page entrante arrive du côté vers lequel on va.
    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: viewModel.tabMovesForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: viewModel.tabMovesForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    var body: some View {
        VStack(spacing: 6) {
            header
            ZStack {
                switch viewModel.tab {
                case .home:
                    home
                        .measuredHeight(for: .home, in: viewModel)
                        .transition(pageTransition)
                case .screenshots:
                    ScreenshotsView()
                        .measuredHeight(for: .screenshots, in: viewModel)
                        .transition(pageTransition)
                case .shelf:
                    ShelfView()
                        .measuredHeight(for: .shelf, in: viewModel)
                        .transition(pageTransition)
                }
            }
            // Pas de découpe ici : la lueur des pochettes doit pouvoir déborder. La forme de la pastille
            // coupe déjà ce qui sort de ses bords, y compris les pages qui glissent.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var home: some View {
        switch Appearance.HomeLayout(rawValue: layoutRaw) ?? .musicAndCalendar {
        case .musicAndCalendar:
            HStack(alignment: .top, spacing: 18) {
                MusicPlayerView()
                CalendarView()
                    .frame(width: 215)
            }
        case .musicOnly:
            MusicPlayerView()
        case .calendarOnly:
            CalendarView()
        }
    }

    /// Bandeau supérieur à hauteur de la découpe : onglets et météo à gauche ; appareils Bluetooth, batterie et réglages à droite.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: compact ? 3 : 6) {
                ForEach(tabs) { tab in
                    TabButton(tab: tab, isSelected: viewModel.tab == tab) {
                        viewModel.select(tab)
                    }
                }
                Spacer(minLength: 0)
                // Collée à l'encoche, en miroir des appareils Bluetooth ; un code reçu prend sa place.
                CodeOrWeatherView()
                    .padding(.trailing, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: viewModel.cutoutSize.width)

            HStack(spacing: compact ? 6 : 10) {
                // Collés à l'encoche ; la batterie du Mac reste au bord droit.
                RecordingStopButton()
                DownloadSpeedView()
                    .padding(.leading, 4)
                if showBluetooth {
                    BluetoothDevicesView()
                        .padding(.leading, 4)
                }
                Spacer(minLength: 0)
                if showCaffeine { CaffeineButton() }
                BatteryStatusView()
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: viewModel.cutoutSize.height)
    }
}

private struct TabButton: View {
    let tab: PillTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 22)
                .background(Capsule().fill(isSelected ? Color.white.opacity(0.18) : .clear))
                .foregroundStyle(isSelected ? .white : .gray)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Enregistrement d'écran en cours : point rouge et durée ; un clic l'arrête (comme ⌘⌃Échap).
private struct RecordingStopButton: View {
    @ObservedObject private var recorder = ScreenRecordingManager.shared
    @State private var hovering = false

    var body: some View {
        if let start = recorder.startedAt {
            Button { recorder.stop() } label: {
                HStack(spacing: 5) {
                    if hovering {
                        Image(systemName: "stop.fill").font(.system(size: 8, weight: .bold))
                    } else {
                        RecordingDot()
                    }
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        Text(CompactPillView.elapsed(since: start, at: context.date))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    }
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(.red.opacity(hovering ? 0.28 : 0.16)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Arrêter l'enregistrement")
            .padding(.leading, 4)
        }
    }
}

/// Tasse de café : garde le Mac éveillé tant qu'elle est pleine.
private struct CaffeineButton: View {
    @ObservedObject private var caffeine = CaffeineManager.shared

    var body: some View {
        Button { caffeine.toggle() } label: {
            Image(systemName: caffeine.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 12))
                .foregroundStyle(caffeine.isActive ? Color.orange : .gray)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(caffeine.isActive ? "Mac maintenu éveillé — cliquer pour rétablir la veille" : "Garder le Mac éveillé")
    }
}
