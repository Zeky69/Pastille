import AppKit
import Combine
import IOBluetooth
import SwiftUI

/// Appareil Bluetooth connecté qui annonce sa batterie.
struct BluetoothDevice: Identifiable, Equatable {
    var id: String
    var name: String
    var symbol: String
    /// Niveau affiché : le plus bas des écouteurs pour des AirPods, sinon le niveau principal.
    var level: Int
    /// Détail pour l'infobulle (« G 80 % · D 75 % · Boîtier 40 % »).
    var detail: String
    /// Niveaux bruts (écouteurs, boîtier, principal), pour repérer une recharge.
    var levels: [String: Int]
    var isCharging = false
}

/// Batterie des appareils Bluetooth, lue dans `system_profiler` (AirPods, claviers, souris Apple),
/// complétée par le module Bluetooth de macOS pour les casques tiers (Sennheiser, Sony…).
@MainActor
final class BluetoothManager: ObservableObject {
    static let shared = BluetoothManager()

    @Published private(set) var devices: [BluetoothDevice] = []
    /// Appareil qui vient de se connecter (batterie pas encore connue : niveau -1).
    let connections = PassthroughSubject<BluetoothDevice, Never>()

    private let connectionObserver = ConnectionObserver()
    private var startedAt = Date()
    private var connectWork: [DispatchWorkItem] = []

    private var poll: Timer?
    /// macOS n'expose pas l'état de charge : un niveau qui monte entre deux lectures veut dire « en charge »,
    /// un niveau qui baisse veut dire « plus en charge ».
    private var charging: [String: Bool] = [:]
    private var lastLevels: [String: [String: Int]] = [:]
    private let queue = DispatchQueue(label: "pastille.bluetooth")

    func start() {
        startedAt = Date()
        schedulePoll(every: 120)
        refresh()
        connectionObserver.start()
    }

    // MARK: - Connexion d'un appareil

    /// Appelé par macOS dès qu'un appareil se connecte. La batterie n'est connue qu'après
    /// quelques instants : la pastille affiche l'appareil tout de suite, puis l'anneau dès qu'il arrive.
    fileprivate func deviceConnected(_ device: IOBluetoothDevice) {
        // macOS signale aussi les appareils déjà connectés au lancement : on les ignore.
        guard Date().timeIntervalSince(startedAt) > 3, let address = device.addressString else { return }
        let id = Self.normalize(address)
        let audio = device.deviceClassMajor == UInt32(kBluetoothDeviceClassMajorAudio)
        connections.send(BluetoothDevice(
            id: id,
            name: device.name ?? "Appareil",
            symbol: Self.symbol(minorType: audio ? "headphones" : nil, productID: nil, name: device.name ?? ""),
            level: -1,
            detail: "",
            levels: [:]
        ))
        connectWork.forEach { $0.cancel() }
        // La batterie d'un casque met parfois plusieurs secondes à remonter après la connexion.
        connectWork = [1, 2.5, 5, 9, 15].map { delay in
            let work = DispatchWorkItem { BluetoothManager.shared.refresh() }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    /// Les anneaux ne se voient que pastille ouverte : lecture toutes les 20 s quand elle l'est,
    /// toutes les 2 min sinon (juste assez pour repérer une recharge).
    func setVisible(_ visible: Bool) {
        schedulePoll(every: visible ? 20 : 120)
        if visible { refresh() }
    }

    private func schedulePoll(every interval: TimeInterval) {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { BluetoothManager.shared.refresh() }
        }
        poll?.tolerance = interval / 4
    }

    func refresh() {
        queue.async {
            let fallback = Self.bluetoothLevels()
            let read = Self.read(fallback: fallback)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let manager = BluetoothManager.shared
                    let devices = manager.withChargingState(read)
                    if manager.devices != devices {
                        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { manager.devices = devices }
                    }
                }
            }
        }
    }

    private func withChargingState(_ devices: [BluetoothDevice]) -> [BluetoothDevice] {
        let result = devices.map { device -> BluetoothDevice in
            var device = device
            if let previous = lastLevels[device.id] {
                let deltas = device.levels.compactMap { key, value in previous[key].map { value - $0 } }
                if deltas.contains(where: { $0 > 0 }) {
                    charging[device.id] = true
                } else if deltas.contains(where: { $0 < 0 }) {
                    charging[device.id] = false
                }
            }
            lastLevels[device.id] = device.levels
            device.isCharging = charging[device.id] ?? false
            return device
        }
        // Appareil déconnecté : on oublie son état.
        let connected = Set(devices.map(\.id))
        lastLevels = lastLevels.filter { connected.contains($0.key) }
        charging = charging.filter { connected.contains($0.key) }
        return result
    }

    /// Niveaux connus du module Bluetooth (propriétés non publiques d'IOBluetoothDevice), par adresse.
    /// Dans un même processus, ces valeurs restent figées après une reconnexion : on les lit donc
    /// dans un processus neuf (Pastille relancée en mode outil), qui repart toujours de l'état réel.
    nonisolated private static func bluetoothLevels() -> [String: [String: Int]] {
        guard let executable = Bundle.main.executableURL else { return [:] }
        let process = Process()
        process.executableURL = executable
        process.arguments = [levelsArgument]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (try? JSONSerialization.jsonObject(with: data) as? [String: [String: Int]]) ?? [:]
    }

    nonisolated static let levelsArgument = "--bluetooth-levels"

    /// Vérification : le lecteur de batteries (processus neuf) répond-il correctement ?
    nonisolated static func levelsReaderWorks() -> Bool {
        guard let executable = Bundle.main.executableURL else { return false }
        let process = Process()
        process.executableURL = executable
        process.arguments = [levelsArgument]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 && (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    /// Mode outil : écrit les niveaux en JSON sur la sortie standard.
    nonisolated static func printLevels() {
        var result: [String: [String: Int]] = [:]
        for device in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [] where device.isConnected() {
            guard let address = device.addressString else { continue }
            var levels: [String: Int] = [:]
            for (key, selector) in [("main", "batteryPercentSingle"), ("left", "batteryPercentLeft"),
                                    ("right", "batteryPercentRight"), ("case", "batteryPercentCase")] {
                guard device.responds(to: Selector(selector)),
                      let value = (device.value(forKey: selector) as? NSNumber)?.intValue, value > 0 else { continue }
                levels[key] = value
            }
            if !levels.isEmpty { result[normalize(address)] = levels }
        }
        if let data = try? JSONSerialization.data(withJSONObject: result) {
            FileHandle.standardOutput.write(data)
        }
    }

    /// Version à jour (batterie lue) d'un appareil, d'après son adresse.
    func current(_ device: BluetoothDevice) -> BluetoothDevice {
        guard var match = devices.first(where: { Self.normalize($0.id) == device.id }) else { return device }
        match.id = device.id
        return match
    }

    /// « 80-c3-ba-66-f4-b6 » et « 80:C3:BA:66:F4:B6 » désignent le même appareil.
    nonisolated static func normalize(_ address: String) -> String {
        address.uppercased().replacingOccurrences(of: "-", with: ":")
    }

    nonisolated private static func read(fallback: [String: [String: Int]]) -> [BluetoothDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = json["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        return controllers
            .flatMap { $0["device_connected"] as? [[String: [String: Any]]] ?? [] }
            .flatMap { $0.compactMap { device(name: $0.key, info: $0.value, fallback: fallback) } }
    }

    nonisolated static func device(name: String, info: [String: Any], fallback: [String: [String: Int]]) -> BluetoothDevice? {
        let extra = (info["device_address"] as? String).flatMap { fallback[normalize($0)] } ?? [:]
        func level(_ key: String, _ fallbackKey: String) -> Int? {
            (info[key] as? String).flatMap { Int($0.filter(\.isNumber)) } ?? extra[fallbackKey]
        }
        let left = level("device_batteryLevelLeft", "left")
        let right = level("device_batteryLevelRight", "right")
        let caseLevel = level("device_batteryLevelCase", "case")
        let main = level("device_batteryLevelMain", "main")

        let buds = [left, right].compactMap { $0 }
        guard let shown = buds.min() ?? main ?? caseLevel else { return nil }

        var parts: [String] = []
        if let left { parts.append("G \(left) %") }
        if let right { parts.append("D \(right) %") }
        if let caseLevel { parts.append("Boîtier \(caseLevel) %") }
        if parts.isEmpty, let main { parts.append("\(main) %") }

        return BluetoothDevice(
            id: info["device_address"] as? String ?? name,
            name: name,
            symbol: symbol(minorType: info["device_minorType"] as? String,
                           productID: info["device_productID"] as? String,
                           name: name),
            level: shown,
            detail: parts.joined(separator: " · "),
            levels: ["left": left, "right": right, "case": caseLevel, "main": main].compactMapValues { $0 }
        )
    }

    /// Symbole SF de l'appareil, d'après son type et, pour Apple, son identifiant produit.
    nonisolated private static func symbol(minorType: String?, productID: String?, name: String) -> String {
        let candidates: [String]
        switch productID?.lowercased() {
        case "0x200e", "0x2014", "0x2024", "0x2027": candidates = ["airpods.pro", "airpodspro"]
        case "0x200a", "0x201f": candidates = ["airpods.max", "airpodsmax"]
        case "0x2013", "0x2019", "0x201b": candidates = ["airpods.gen3", "airpods"]
        case "0x2002", "0x200f", "0x2012": candidates = ["airpods"]
        default:
            switch minorType?.lowercased() ?? "" {
            case let t where t.contains("headphone") || t.contains("headset"): candidates = ["headphones"]
            case let t where t.contains("keyboard"): candidates = ["keyboard.fill"]
            case let t where t.contains("mouse"): candidates = ["magicmouse.fill", "computermouse.fill"]
            case let t where t.contains("trackpad"): candidates = ["rectangle.and.hand.point.up.left.fill"]
            case let t where t.contains("gamepad") || t.contains("joystick"): candidates = ["gamecontroller.fill"]
            case let t where t.contains("speaker"): candidates = ["hifispeaker.fill"]
            default:
                candidates = name.lowercased().contains("airpods") ? ["airpods"] : ["dot.radiowaves.left.and.right"]
            }
        }
        return candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
            ?? "dot.radiowaves.left.and.right"
    }
}

/// Reçoit les notifications de connexion d'IOBluetooth (qui demande un objet Objective-C).
private final class ConnectionObserver: NSObject {
    private var registration: IOBluetoothUserNotification?

    func start() {
        registration = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    @objc private func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { BluetoothManager.shared.deviceConnected(device) }
        }
    }
}

