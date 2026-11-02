import Combine
import ServiceManagement
import SwiftUI

/// État de chaque autorisation macOS et des fonctions non officielles, avec un raccourci pour corriger.
struct PermissionsSettings: View {
    @State private var permissions = HealthCheck.permissions()
    @State private var features: [HealthCheck.Item] = []
    @State private var checking = false
    /// Les autorisations se revérifient toutes seules (on revient souvent des Réglages Système).
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                ForEach(permissions) { HealthRow(item: $0) }
            } header: {
                Text("Autorisations de macOS")
            } footer: {
                Text("Sans une autorisation, seule la fonction concernée s'arrête ; le reste de Pastille continue.")
            }

            Section {
                if features.isEmpty {
                    HStack { ProgressView().controlSize(.small); Text("Vérification…").foregroundStyle(.secondary) }
                } else {
                    ForEach(features) { HealthRow(item: $0) }
                }
            } header: {
                HStack {
                    Text("Fonctions avancées")
                    Spacer()
                    Button(checking ? "Vérification…" : "Revérifier") { checkFeatures() }
                        .disabled(checking)
                        .controlSize(.small)
                }
            } footer: {
                Text("Ces fonctions passent par des chemins non officiels de macOS : une mise à jour peut en casser une. Elle s'affiche alors ici en orange, et Pastille continue sans elle.")
            }
        }
        .formStyle(.grouped)
        .onAppear { checkFeatures() }
        .onReceive(tick) { _ in
            let fresh = HealthCheck.permissions()
            if fresh != permissions { permissions = fresh }
        }
    }

    private func checkFeatures() {
        checking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = HealthCheck.features()
            DispatchQueue.main.async {
                features = result
                checking = false
            }
        }
    }
}

struct HealthRow: View {
    let item: HealthCheck.Item

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                Text(statusText).font(.caption).foregroundStyle(statusColor)
            }
            Spacer()
            if item.status != .ok, let pane = item.settingsPane {
                Button("Ouvrir") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)
        }
        .help(item.detail)
    }

    private var color: Color {
        switch item.status {
        case .ok: .green
        case .missing: .red
        case .broken: .orange
        case .unknown: .gray
        }
    }

    private var statusColor: Color {
        item.status == .ok ? .secondary : color
    }

    private var statusSymbol: String {
        switch item.status {
        case .ok: "checkmark.circle.fill"
        case .missing: "xmark.circle.fill"
        case .broken: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    private var statusText: String {
        switch item.status {
        case .ok: item.detail
        case .missing: "Non autorisé — \(item.detail.prefix(1).lowercased() + item.detail.dropFirst())"
        case .broken(let reason): "En panne : \(reason)"
        case .unknown(let reason): reason
        }
    }
}

// MARK: - Général
