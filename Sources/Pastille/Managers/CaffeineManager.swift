import Combine
import Foundation
import IOKit
import IOKit.pwr_mgt

/// État de la tasse de café.
enum CaffeineMode: Equatable {
    case off
    /// L'écran et le Mac restent éveillés tant que le capot est ouvert.
    case awake
    /// Super tasse : le Mac ne dort pas même capot fermé (`pmset disablesleep`).
    case lidClosed
}

/// Garde le Mac (et l'écran) éveillé tant que la tasse est activée.
/// L'assertion est rendue à macOS en désactivant, ou automatiquement si Pastille quitte.
///
/// Super tasse (Cmd-clic) : seule la veille désactivée de macOS (`pmset -a disablesleep 1`, réservée
/// à l'administrateur) empêche la veille capot fermé. La première fois, macOS demande le mot de passe
/// une seule fois pour autoriser Pastille à lancer exactement ces deux commandes (fichier
/// /etc/sudoers.d/pastille) ; ensuite plus aucune question.
@MainActor
final class CaffeineManager: ObservableObject {
    static let shared = CaffeineManager()

    @Published private(set) var mode: CaffeineMode = .off
    var isActive: Bool { mode != .off }
    var isSuper: Bool { mode == .lidClosed }
    /// Envoyé à chaque bascule (nouvel état), pour un bref affichage dans la pastille fermée.
    let toggled = PassthroughSubject<CaffeineMode, Never>()

    private var assertion: IOPMAssertionID = 0
    private var hasAssertion = false
    private var busy = false
    private var cancellables = Set<AnyCancellable>()

    /// Pastille a coupé la veille : à rétablir si elle a quitté sans le faire (plantage, arrêt forcé).
    private static let sleepDisabledKey = "caffeine.sleepDisabledByPastille"
    /// Super tasse coupée sur batterie à ce niveau, pour ne pas vider le Mac dans un sac.
    nonisolated static let lowBatteryCutoff = 10

    func start() {
        if UserDefaults.standard.bool(forKey: Self.sleepDisabledKey) {
            if Self.isSleepDisabled { _ = Self.runPmset(disable: false) }
            UserDefaults.standard.removeObject(forKey: Self.sleepDisabledKey)
        }
        BatteryManager.shared.$level
            .combineLatest(BatteryManager.shared.$isPluggedIn, BatteryManager.shared.$hasBattery)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level, plugged, hasBattery in
                guard let self, self.isSuper, !self.busy,
                      Self.shouldStopForBattery(level: level, pluggedIn: plugged, hasBattery: hasBattery) else { return }
                self.setSleepDisabled(false) { _ in self.apply(.awake) }
            }
            .store(in: &cancellables)
    }

    /// Clic : allume ou éteint la tasse (éteint aussi la super tasse).
    func toggle() {
        guard !busy else { return }
        if isSuper {
            setSleepDisabled(false) { _ in self.apply(.off) }
        } else {
            apply(isActive ? .off : .awake)
        }
    }

    /// Cmd-clic : super tasse, ou retour à l'arrêt si elle est déjà active.
    func toggleSuper() {
        guard !busy else { return }
        if isSuper {
            setSleepDisabled(false) { _ in self.apply(.off) }
        } else {
            setSleepDisabled(true) { ok in if ok { self.apply(.lidClosed) } }
        }
    }

    /// À l'arrêt de Pastille : la veille doit revenir.
    func stop() {
        guard UserDefaults.standard.bool(forKey: Self.sleepDisabledKey) else { return }
        if Self.runPmset(disable: false) {
            UserDefaults.standard.removeObject(forKey: Self.sleepDisabledKey)
        }
    }

    nonisolated static func shouldStopForBattery(level: Int, pluggedIn: Bool, hasBattery: Bool) -> Bool {
        hasBattery && !pluggedIn && level <= lowBatteryCutoff
    }

    // MARK: - Interne

    private func apply(_ newMode: CaffeineMode) {
        if newMode == .off {
            if hasAssertion { IOPMAssertionRelease(assertion) }
            hasAssertion = false
        } else if !hasAssertion {
            hasAssertion = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Pastille garde le Mac éveillé" as CFString,
                &assertion
            ) == kIOReturnSuccess
        }
        mode = newMode != .off && !hasAssertion ? .off : newMode
        toggled.send(mode)
    }

    /// Lance pmset hors du fil principal (la demande de mot de passe peut attendre l'utilisateur).
    private func setSleepDisabled(_ disable: Bool, completion: @escaping @MainActor (Bool) -> Void) {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            var ok = Self.runPmset(disable: disable)
            if !ok, disable { ok = Self.authorizeAndDisable() }
            ok = ok && Self.isSleepDisabled == disable
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if ok {
                        if disable {
                            UserDefaults.standard.set(true, forKey: Self.sleepDisabledKey)
                        } else {
                            UserDefaults.standard.removeObject(forKey: Self.sleepDisabledKey)
                        }
                    }
                    CaffeineManager.shared.busy = false
                    completion(ok)
                }
            }
        }
    }

    /// Valeur réelle de la veille désactivée, lue sans droits dans le registre d'IOKit.
    nonisolated static var isSleepDisabled: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? Bool) ?? false
    }

    /// `sudo -n` : ne demande jamais rien, échoue si Pastille n'est pas encore autorisée.
    @discardableResult
    nonisolated private static func runPmset(disable: Bool) -> Bool {
        run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", disable ? "1" : "0"])
    }

    /// Une seule demande de mot de passe : autorise les deux commandes pmset sans mot de passe,
    /// puis coupe la veille.
    nonisolated private static func authorizeAndDisable() -> Bool {
        let user = NSUserName()
        guard !user.isEmpty, user.allSatisfy({ $0.isLetter || $0.isNumber || "._-".contains($0) }) else { return false }
        let rule = sudoersRule(for: user)
        let script = "t=$(/usr/bin/mktemp) && /usr/bin/printf '%s\\\\n' '\(rule)' > $t"
            + " && /usr/sbin/visudo -cf $t >/dev/null"
            + " && /usr/bin/install -m 0440 -o root -g wheel $t /private/etc/sudoers.d/pastille"
            + "; /bin/rm -f $t; /usr/bin/pmset -a disablesleep 1"
        let prompt = "Pastille a besoin de votre autorisation, une seule fois, pour garder le Mac éveillé capot fermé."
        return run("/usr/bin/osascript", [
            "-e", "do shell script \"\(script)\" with prompt \"\(prompt)\" with administrator privileges",
        ])
    }

    nonisolated static func sudoersRule(for user: String) -> String {
        "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
    }

    nonisolated private static func run(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
