import AppKit
import Combine
import CoreAudio

/// Appel en cours (visio ou audio), repéré sans autorisation : Core Audio dit quelle app capte le micro
/// et laquelle joue du son. La logique (début, fin) est dans `CallTracker`.
/// Au repos, rien ne tourne : on se réveille quand un micro s'allume, puis on relève chaque seconde.
@MainActor
final class CallManager: ObservableObject {
    static let shared = CallManager()

    @Published private(set) var call: CallTracker.Call?
    /// L'appel dure depuis plus d'une heure : la durée prend une place de plus (« 1:02:03 »).
    @Published private(set) var isLongCall = false
    private var longCallWork: DispatchWorkItem?
    /// Micro coupé depuis la pastille.
    @Published private(set) var isMuted = false

    private var tracker = CallTracker()
    private var poll: Timer?
    private var watchedDevices: [AudioObjectID] = []
    private let listenerQueue = DispatchQueue.main
    /// Musique mise en pause par Pastille au début de l'appel : on la relance à la fin.
    private var pausedMusic = false

    func start() {
        restoreMicIfLeftMuted()
        watchInputDevices()
        var devices = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, listenerQueue) { _, _ in
            MainActor.assumeIsolated { CallManager.shared.watchInputDevices() }
        }
        check()
    }

    var appName: String {
        guard let id = call?.app.bundleID else { return "Appel" }
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id }), let name = app.localizedName {
            return name
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? "Appel"
    }

    var appIcon: NSImage? {
        guard let id = call?.app.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Ramène l'app de l'appel au premier plan.
    func openApp() {
        guard let id = call?.app.bundleID else { return }
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id }) {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    // MARK: - Relevés

    /// Un micro s'allume ou s'éteint quelque part : on (re)vérifie, et on relève chaque seconde tant
    /// qu'un micro tourne ou qu'un appel est en cours.
    private func watchInputDevices() {
        let inputs = Self.inputDevices()
        guard inputs != watchedDevices else { return }
        watchedDevices = inputs
        for device in inputs {
            var running = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(device, &running, listenerQueue) { _, _ in
                MainActor.assumeIsolated { CallManager.shared.check() }
            }
        }
    }

    private func check() {
        let micRunning = watchedDevices.contains(where: Self.isRunning)
        if micRunning || call != nil {
            startPolling()
        } else {
            poll?.invalidate()
            poll = nil
        }
        let change = tracker.update(Self.audioClients(micRunning: micRunning), at: Date())
        apply(change)
    }

    private func startPolling() {
        guard poll == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { CallManager.shared.check() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func apply(_ change: CallTracker.Change?) {
        switch change {
        case .started(let new)?:
            call = new
            let work = DispatchWorkItem { CallManager.shared.isLongCall = true }
            longCallWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(3600 - Date().timeIntervalSince(new.startedAt), 0), execute: work)
            if Appearance.bool(Appearance.callKey), Appearance.bool(Appearance.callPauseMusicKey), MusicManager.shared.isPlaying {
                MusicManager.shared.playPause()
                pausedMusic = true
            }
        case .ended?:
            call = nil
            longCallWork?.cancel()
            isLongCall = false
            if isMuted { setMuted(false) }
            if pausedMusic, !MusicManager.shared.isPlaying { MusicManager.shared.playPause() }
            pausedMusic = false
        case nil:
            break
        }
    }

    // MARK: - Micro coupé

    func toggleMute() { setMuted(!isMuted) }

    /// On coupe le micro par défaut du Mac (toutes les apps l'entendent coupé). Si le micro n'a pas
    /// d'interrupteur, on baisse son volume à zéro, et on remet le volume d'avant ensuite.
    private func setMuted(_ muted: Bool) {
        guard let device = Self.defaultInput() else { return }
        if Self.setInputMute(device, muted) {
            isMuted = muted
            return
        }
        if muted {
            guard let volume = Self.inputVolume(device), Self.setInputVolume(device, 0) else { return }
            UserDefaults.standard.set(volume, forKey: Self.savedVolumeKey)
            isMuted = true
        } else {
            let saved = UserDefaults.standard.object(forKey: Self.savedVolumeKey) as? Float ?? 0.75
            _ = Self.setInputVolume(device, saved)
            UserDefaults.standard.removeObject(forKey: Self.savedVolumeKey)
            isMuted = false
        }
    }

    /// Volume du micro d'avant la coupure, gardé au cas où Pastille quitte pendant l'appel.
    private static let savedVolumeKey = "call.savedMicVolume"

    private func restoreMicIfLeftMuted() {
        guard let saved = UserDefaults.standard.object(forKey: Self.savedVolumeKey) as? Float,
              let device = Self.defaultInput() else { return }
        _ = Self.setInputVolume(device, saved)
        UserDefaults.standard.removeObject(forKey: Self.savedVolumeKey)
    }

    var canMute: Bool {
        guard let device = Self.defaultInput() else { return false }
        return Self.isSettable(device, kAudioDevicePropertyMute) || Self.isSettable(device, kAudioDevicePropertyVolumeScalar)
    }

    // MARK: - Core Audio

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var addr = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var addr = address(selector, scope: scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    /// Appareils qui ont des entrées (micros).
    private static func inputDevices() -> [AudioObjectID] {
        objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).filter { device in
            var addr = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
            var size: UInt32 = 0
            return AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr && size > 0
        }
    }

    private static func isRunning(_ device: AudioObjectID) -> Bool {
        (uint32(device, kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 0) != 0
    }

    private static func defaultInput() -> AudioObjectID? {
        uint32(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice).flatMap { $0 == 0 ? nil : $0 }
    }

    /// Qui capte le micro et qui joue du son. Depuis macOS 14.2, Core Audio le dit par processus ;
    /// avant, on suppose que l'app d'appel ouverte est celle qui utilise le micro allumé.
    private static func audioClients(micRunning: Bool) -> [AudioClient] {
        if #available(macOS 14.2, *) {
            return objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList).compactMap { process in
                let input = (uint32(process, kAudioProcessPropertyIsRunningInput) ?? 0) != 0
                let output = (uint32(process, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0
                guard input || output else { return nil }
                return AudioClient(bundleID: bundleID(of: process), processName: uint32(process, kAudioProcessPropertyPID).flatMap { processName(pid_t($0)) },
                                   usesInput: input, usesOutput: output)
            }
        }
        guard micRunning else { return [] }
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, let found = CallDetector.app(for: AudioClient(bundleID: id, usesInput: true, usesOutput: false)),
                  !found.isBrowser else { return nil }
            return AudioClient(bundleID: id, usesInput: true, usesOutput: false)
        }
    }

    @available(macOS 14.2, *)
    private static func bundleID(of process: AudioObjectID) -> String? {
        var addr = address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &addr, 0, nil, &size, &value) == noErr, let value else { return nil }
        let id = value.takeRetainedValue() as String
        return id.isEmpty ? nil : id
    }

    private static func processName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func isSettable(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var addr = address(selector, scope: kAudioObjectPropertyScopeInput)
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &addr) && AudioObjectIsPropertySettable(device, &addr, &settable) == noErr && settable.boolValue
    }

    private static func setInputMute(_ device: AudioObjectID, _ muted: Bool) -> Bool {
        guard isSettable(device, kAudioDevicePropertyMute) else { return false }
        var addr = address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput)
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private static func inputVolume(_ device: AudioObjectID) -> Float? {
        var addr = address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func setInputVolume(_ device: AudioObjectID, _ volume: Float) -> Bool {
        guard isSettable(device, kAudioDevicePropertyVolumeScalar) else { return false }
        var addr = address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput)
        var value = Float32(volume)
        return AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }
}
