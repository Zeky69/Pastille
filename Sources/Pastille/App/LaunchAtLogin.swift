import ServiceManagement

/// Lancement de Pastille à l'ouverture de session, via les « Éléments de connexion » de macOS.
/// L'état vient toujours de macOS (rien n'est mémorisé de notre côté), pour ne jamais afficher un réglage faux.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// macOS a enregistré la demande mais attend une validation dans Réglages Système › Éléments de connexion.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Active ou désactive ; renvoie un message d'erreur lisible si macOS refuse.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
