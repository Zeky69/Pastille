import Combine
import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
    @AppStorage(Settings.openOnHoverKey) private var openOnHover = true
    @AppStorage(Settings.hoverDelayKey) private var hoverDelay = 0.15
    @AppStorage(Settings.hapticsKey) private var haptics = true
    @AppStorage(Settings.hideInFullscreenKey) private var hideInFullscreen = true
    @AppStorage(Settings.swipePagesKey) private var swipePages = true
    @AppStorage(Settings.showMenuBarIconKey) private var showMenuBarIcon = true
    @AppStorage(Settings.tidyDesktopScreenshotsKey) private var tidyDesktop = true
    @AppStorage(Settings.checkForUpdatesKey) private var checkForUpdates = true
    @State private var confirmReset = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchNeedsApproval = LaunchAtLogin.needsApproval
    @State private var launchError: String?

    /// Relit l'état réel dans macOS (il peut changer depuis Réglages Système).
    private func refreshLaunchState() {
        launchAtLogin = LaunchAtLogin.isEnabled
        launchNeedsApproval = LaunchAtLogin.needsApproval
    }

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
                Toggle("Se cacher pendant les apps en plein écran", isOn: $hideInFullscreen)
                Toggle("Glisser à deux doigts pour changer de page", isOn: $swipePages)
                Toggle("Icône dans la barre des menus", isOn: $showMenuBarIcon)
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        launchError = LaunchAtLogin.set(enabled)
                        refreshLaunchState()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ouvrir Pastille au démarrage du Mac")
                        if let launchError {
                            Text("macOS a refusé : \(launchError)").font(.caption).foregroundStyle(.red)
                        } else if launchNeedsApproval {
                            HStack(spacing: 6) {
                                Text("À valider dans les Éléments de connexion de macOS.")
                                    .font(.caption).foregroundStyle(.orange)
                                Button("Ouvrir") { LaunchAtLogin.openLoginItemsSettings() }
                                    .controlSize(.small)
                            }
                        }
                    }
                }
                .onAppear { refreshLaunchState() }
            }
            Section("Mises à jour") {
                UpdateStatusRow()
                Toggle("Rechercher automatiquement les nouvelles versions", isOn: $checkForUpdates)
            }
            Section("Captures d'écran") {
                LabeledContent("Dossier") {
                    Button(ScreenshotManager.shared.folderName) { ScreenshotManager.shared.revealFolder() }
                        .buttonStyle(.link)
                }
                Toggle("Ranger dans ce dossier les captures tombées sur le Bureau", isOn: $tidyDesktop)
            }
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Réinitialiser l'apparence")
                        Text("Préréglage Classique, toutes les activités réactivées.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Réinitialiser…") { confirmReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Revenir à l'affichage d'origine ?", isPresented: $confirmReset) {
            Button("Réinitialiser", role: .destructive) {
                withAnimation(.snappy) { Appearance.resetToDefaults() }
            }
        } message: {
            Text("L'apparence et les activités reprennent leurs réglages par défaut. Le survol, le retour haptique et le lancement au démarrage ne changent pas.")
        }
    }
}

/// Version installée, et la nouvelle version quand il y en a une (installée en un clic).
private struct UpdateStatusRow: View {
    @ObservedObject private var updates = UpdateManager.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pastille \(UpdateManager.currentVersion)")
                status
                    .font(.caption)
            }
            Spacer()
            action
        }
    }

    @ViewBuilder private var status: some View {
        switch updates.state {
        case .idle: Text("Vérifiée sur GitHub au lancement, puis toutes les 6 heures.").foregroundStyle(.secondary)
        case .checking: Text("Recherche en cours…").foregroundStyle(.secondary)
        case .upToDate: Text("C'est la dernière version.").foregroundStyle(.secondary)
        case let .available(release): Text("La version \(release.version) est disponible.").foregroundStyle(.blue)
        case let .installing(release): Text("Installation de la version \(release.version)… Pastille va redémarrer.").foregroundStyle(.secondary)
        case let .failed(message): Text(message).foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var action: some View {
        switch updates.state {
        case .available:
            HStack(spacing: 6) {
                Button("Nouveautés") { updates.openReleasePage() }
                Button("Installer") { updates.install() }
                    .buttonStyle(.borderedProminent)
            }
        case .checking, .installing:
            ProgressView().controlSize(.small)
        default:
            Button("Rechercher") { updates.check() }
        }
    }
}
