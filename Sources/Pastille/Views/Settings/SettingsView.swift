import Combine
import ServiceManagement
import SwiftUI

/// Réglages en quatre onglets : Apparence (préréglages + personnalisation), Activités, Autorisations, Général.
/// Tout s'applique en direct à la pastille.
struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettings()
                .tabItem { Label("Apparence", systemImage: "paintbrush.fill") }
            ActivitySettings()
                .tabItem { Label("Activités", systemImage: "capsule.fill") }
            PermissionsSettings()
                .tabItem { Label("Autorisations", systemImage: "checkmark.shield.fill") }
            GeneralSettings()
                .tabItem { Label("Général", systemImage: "gearshape.fill") }
        }
        .frame(width: 580, height: 640)
    }
}

// MARK: - Apparence
