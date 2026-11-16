import Combine
import SwiftUI

/// Assistant du premier lancement : une autorisation par page, expliquée avant que macOS pose sa question.
/// Chaque page peut être passée (« Plus tard ») ; tout se retrouve ensuite dans Réglages › Autorisations.
struct OnboardingView: View {
    let onFinish: () -> Void

    private enum Step: Hashable {
        case welcome
        case permission(Permissions.Kind)
        case finish
    }

    private let steps: [Step] = [.welcome] + Permissions.Kind.allCases.map(Step.permission) + [.finish]
    @State private var index = 0
    @State private var states: [Permissions.Kind: Permissions.State] = Self.readStates()
    /// Autorisations demandées pendant l'assistant : on attend la réponse de macOS.
    @State private var requested: Set<Permissions.Kind> = []
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    /// Les réponses arrivent depuis les fenêtres de macOS ou les Réglages Système : on relit l'état.
    private let tick = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    /// `startAt` : page d'ouverture (aperçus).
    init(startAt: Int = 0, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _index = State(initialValue: startAt)
    }

    private var step: Step { steps[index] }
    private static var permissionCount: Int { Permissions.Kind.allCases.count }

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.top, 34)
                .padding(.horizontal, 40)

            Group {
                switch step {
                case .welcome: welcome
                case .permission(let kind): PermissionPage(
                    info: .of(kind),
                    number: index,
                    total: Self.permissionCount,
                    state: states[kind] ?? .notAsked,
                    waiting: requested.contains(kind)
                )
                case .finish: finish
                }
            }
            .id(index)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)

            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 580, height: 620)
        .background(.background)
        .onReceive(tick) { _ in refresh() }
    }

    // MARK: - Progression

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.permissionCount, id: \.self) { i in
                let kind = Permissions.Kind.allCases[i]
                Capsule()
                    .fill(segmentColor(position: i + 1, kind: kind))
                    .frame(height: 4)
            }
        }
        .opacity(step == .welcome ? 0 : 1)
        .animation(.easeInOut(duration: 0.25), value: index)
    }

    private func segmentColor(position: Int, kind: Permissions.Kind) -> Color {
        if position == index { return .accentColor }
        if position < index { return states[kind] == .granted ? .green : Color.secondary.opacity(0.45) }
        return Color.secondary.opacity(0.18)
    }

    // MARK: - Pages d'accueil et de fin

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            VStack(spacing: 8) {
                Text("Bienvenue dans Pastille")
                    .font(.system(size: 26, weight: .bold))
                Text("Pastille transforme l'encoche de ton Mac : musique, calendrier, météo, batterie, captures…\nPour certaines fonctions, macOS a besoin de ton accord.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(symbol: "list.number", color: .blue,
                        text: "On les voit une par une, et tu sais à chaque fois à quoi elle sert avant que macOS te pose la question.")
                InfoRow(symbol: "hand.raised.fill", color: .orange,
                        text: "Rien n'est obligatoire : « Plus tard » est toujours possible. Sans une autorisation, seule la fonction concernée s'arrête.")
                InfoRow(symbol: "lock.fill", color: .green,
                        text: "Tout reste sur ton Mac. Pastille n'a pas de compte et n'envoie rien sur toi.")
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.5)))
            Spacer(minLength: 0)
        }
    }

    private var finish: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            IconTile(symbol: "checkmark.seal.fill", color: .green)
            VStack(spacing: 8) {
                Text("C'est prêt !")
                    .font(.system(size: 26, weight: .bold))
                Text("Passe la souris sur l'encoche pour ouvrir Pastille.")
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 10) {
                ForEach(Permissions.Kind.allCases) { kind in
                    let info = PermissionInfo.of(kind)
                    HStack(spacing: 8) {
                        Image(systemName: summarySymbol(states[kind]))
                            .foregroundStyle(states[kind] == .granted ? .green : .secondary)
                        Text(info.title)
                            .foregroundStyle(states[kind] == .granted ? .primary : .secondary)
                    }
                    .font(.callout)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.5)))
            Toggle("Ouvrir Pastille au démarrage du Mac", isOn: Binding(
                get: { launchAtLogin },
                set: { LaunchAtLogin.set($0); launchAtLogin = LaunchAtLogin.isEnabled }
            ))
            .toggleStyle(.switch)
            Text("Tu peux tout changer plus tard dans Réglages › Autorisations.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func summarySymbol(_ state: Permissions.State?) -> String {
        switch state {
        case .granted: "checkmark.circle.fill"
        case .unavailable: "clock"
        default: "minus.circle"
        }
    }

    // MARK: - Boutons

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            if index > 0 {
                Button("Retour") { go(to: index - 1) }
                    .buttonStyle(.borderless)
            }
            Spacer()
            switch step {
            case .welcome:
                Button("Tout passer") { go(to: steps.count - 1) }
                    .buttonStyle(.borderless)
                primary("Commencer") { go(to: index + 1) }
            case .permission(let kind):
                let state = states[kind] ?? .notAsked
                if state != .granted, !isUnavailable(state) {
                    Button("Plus tard") { go(to: index + 1) }
                        .controlSize(.large)
                }
                if state == .granted || isUnavailable(state) {
                    primary("Continuer") { go(to: index + 1) }
                } else if state == .denied || kind == .fullDisk {
                    primary("Ouvrir les Réglages Système") { ask(kind) }
                } else {
                    primary(requested.contains(kind) ? "Redemander" : "Autoriser") { ask(kind) }
                }
            case .finish:
                primary("Commencer à utiliser Pastille") { onFinish() }
            }
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
    }

    private func isUnavailable(_ state: Permissions.State) -> Bool {
        if case .unavailable = state { return true }
        return false
    }

    // MARK: - Actions

    private func go(to newIndex: Int) {
        withAnimation(.spring(duration: 0.4, bounce: 0.15)) { index = min(max(newIndex, 0), steps.count - 1) }
    }

    private func ask(_ kind: Permissions.Kind) {
        requested.insert(kind)
        Permissions.request(kind)
        refresh()
    }

    private static func readStates() -> [Permissions.Kind: Permissions.State] {
        Dictionary(uniqueKeysWithValues: Permissions.Kind.allCases.map { ($0, Permissions.state(of: $0)) })
    }

    private func refresh() {
        let fresh = Self.readStates()
        guard fresh != states else { return }
        let newlyGranted = Permissions.Kind.allCases.filter { fresh[$0] == .granted && states[$0] != .granted }
        withAnimation(.easeInOut(duration: 0.25)) { states = fresh }
        // Autorisation de la page en cours accordée (souvent dans Réglages Système) : on revient
        // au premier plan et on passe à la suite.
        guard case .permission(let kind) = step, newlyGranted.contains(kind), requested.contains(kind) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let current = index
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            if index == current { go(to: current + 1) }
        }
    }
}

// MARK: - Page d'une autorisation

private struct PermissionPage: View {
    let info: PermissionInfo
    let number: Int
    let total: Int
    let state: Permissions.State
    let waiting: Bool

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            IconTile(symbol: info.symbol, color: info.color)
            VStack(spacing: 6) {
                Text("Étape \(number) sur \(total) · \(info.optional ? "facultatif" : "recommandé")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(info.title)
                    .font(.system(size: 24, weight: .bold))
                Text(info.summary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(info.benefits, id: \.text) { benefit in
                    InfoRow(symbol: benefit.symbol, color: info.color, text: benefit.text)
                }
                Divider()
                InfoRow(symbol: "lock.fill", color: .green, text: info.privacy)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.5)))
            status
                .frame(minHeight: 40)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .granted:
            Label("Autorisé", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.green)
        case .unavailable(let reason):
            Label(reason, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .notAsked where waiting, .denied where waiting && info.opensSettings:
            HStack(alignment: .top, spacing: 8) {
                ProgressView().controlSize(.small)
                Text(info.hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .denied where waiting:
            Label("Pas autorisé pour l'instant : active Pastille dans Réglages Système, volet « \(info.systemName) ».",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        default:
            Text("Autorisation macOS : \(info.systemName)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Éléments communs

private struct IconTile: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 76, height: 76)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(color.gradient))
            .shadow(color: color.opacity(0.35), radius: 12, y: 5)
    }
}

private struct InfoRow: View {
    let symbol: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Textes

struct PermissionInfo {
    struct Benefit { let symbol: String; let text: String }

    let title: String
    /// Nom de l'autorisation dans Réglages Système › Confidentialité et sécurité.
    let systemName: String
    let symbol: String
    let color: Color
    let summary: String
    let benefits: [Benefit]
    let privacy: String
    /// Affiché pendant qu'on attend la réponse.
    let hint: String
    var optional = false
    /// macOS ne pose pas de question : il faut passer par Réglages Système.
    var opensSettings = false

    static func of(_ kind: Permissions.Kind) -> PermissionInfo {
        switch kind {
        case .accessibility:
            PermissionInfo(
                title: "Volume et luminosité", systemName: "Accessibilité",
                symbol: "speaker.wave.2.fill", color: .blue,
                summary: "Quand tu changes le volume ou la luminosité, le niveau s'affiche dans l'encoche à la place de la grosse bulle d'Apple.",
                benefits: [
                    Benefit(symbol: "slider.horizontal.3", text: "Indicateur discret de volume et de luminosité, collé à l'encoche."),
                    Benefit(symbol: "record.circle", text: "Arrêter un enregistrement d'écran depuis l'encoche."),
                ],
                privacy: "Pastille ne réagit qu'aux touches de volume et de luminosité : rien de ce que tu tapes n'est enregistré ni envoyé.",
                hint: "Dans la fenêtre de macOS, choisis « Ouvrir Réglages Système », puis active Pastille dans la liste. Reviens ici ensuite.",
                opensSettings: true
            )
        case .automation:
            PermissionInfo(
                title: "Musique et Spotify", systemName: "Automatisation",
                symbol: "music.note", color: .pink,
                summary: "Pastille demande à Musique et Spotify le morceau en cours, avec sa pochette, pour l'afficher et le piloter.",
                benefits: [
                    Benefit(symbol: "playpause.fill", text: "Lecture, pause, morceau suivant depuis l'encoche."),
                    Benefit(symbol: "photo", text: "Pochette et progression toujours à jour."),
                ],
                privacy: "Pastille ne touche ni à ta bibliothèque ni à tes playlists. YouTube, Deezer et les autres apps n'ont besoin de rien.",
                hint: "Réponds « Autoriser » dans la fenêtre de macOS (une par app ouverte)."
            )
        case .calendar:
            PermissionInfo(
                title: "Calendrier", systemName: "Calendriers",
                symbol: "calendar", color: .red,
                summary: "Tes événements du jour et de la semaine s'affichent dans la pastille ouverte.",
                benefits: [
                    Benefit(symbol: "clock", text: "Ce qui t'attend aujourd'hui, d'un coup d'œil."),
                    Benefit(symbol: "calendar.day.timeline.left", text: "Le reste de la semaine en liste, ou le mois entier."),
                ],
                privacy: "Lecture seule : Pastille ne crée, ne modifie et n'envoie aucun événement.",
                hint: "Réponds dans la fenêtre de macOS (« Autoriser l'accès complet »)."
            )
        case .location:
            PermissionInfo(
                title: "Météo", systemName: "Service de localisation",
                symbol: "cloud.sun.fill", color: .orange,
                summary: "La température et le temps qu'il fait là où tu es, dans la page d'accueil de la pastille.",
                benefits: [
                    Benefit(symbol: "thermometer.medium", text: "Température actuelle, mise à jour toutes les 30 minutes."),
                ],
                privacy: "Ta position est arrondie au kilomètre et envoyée seulement à Open-Meteo (gratuit, sans compte) pour obtenir la météo.",
                hint: "Réponds « Autoriser » dans la fenêtre de macOS.",
                optional: true
            )
        case .bluetooth:
            PermissionInfo(
                title: "Batterie des appareils", systemName: "Bluetooth",
                symbol: "headphones", color: .indigo,
                summary: "Le niveau de batterie de tes AirPods, casques, claviers et souris, et une annonce quand l'un d'eux se connecte.",
                benefits: [
                    Benefit(symbol: "battery.75percent", text: "Batterie de chaque écouteur et du boîtier."),
                    Benefit(symbol: "bolt.horizontal.fill", text: "Annonce dans l'encoche quand un appareil se connecte."),
                ],
                privacy: "Pastille lit seulement les appareils déjà jumelés à ton Mac ; elle ne s'y connecte jamais.",
                hint: "Réponds « Autoriser » dans la fenêtre de macOS."
            )
        case .fullDisk:
            PermissionInfo(
                title: "Codes et Concentration", systemName: "Accès complet au disque",
                symbol: "lock.shield.fill", color: .teal,
                summary: "Pastille repère les codes de vérification reçus dans Messages et Mail, et sait quand un mode Concentration s'active.",
                benefits: [
                    Benefit(symbol: "number", text: "Le code reçu par SMS ou e-mail, copié en un clic depuis l'encoche."),
                    Benefit(symbol: "moon.fill", text: "Ne pas déranger, Sommeil, Travail… annoncés quand ils démarrent."),
                    Benefit(symbol: "folder.fill", text: "Couvre aussi l'étape suivante (Bureau et Téléchargements)."),
                ],
                privacy: "Les messages sont lus uniquement sur ton Mac, seulement pour y trouver un code : rien n'est gardé ni envoyé.",
                hint: "Dans Réglages Système, active Pastille (ou ajoute-la avec le bouton +). Reviens ici ensuite.",
                optional: true,
                opensSettings: true
            )
        case .folders:
            PermissionInfo(
                title: "Captures et téléchargements", systemName: "Fichiers et dossiers",
                symbol: "folder.fill", color: .cyan,
                summary: "Tes dernières captures d'écran apparaissent dans l'encoche, et la progression des téléchargements s'y affiche.",
                benefits: [
                    Benefit(symbol: "camera.viewfinder", text: "Aperçu de la capture qui descend de l'encoche, copiée d'office."),
                    Benefit(symbol: "arrow.down.circle", text: "Progression du téléchargement en cours."),
                ],
                privacy: "Pastille ne regarde que les captures d'écran du Bureau et les téléchargements en cours.",
                hint: "macOS pose deux questions, une pour le Bureau et une pour Téléchargements : réponds « Autoriser » aux deux."
            )
        }
    }
}
