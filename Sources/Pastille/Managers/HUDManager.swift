import AppKit
import AudioToolbox
import CoreAudio

enum HUDKind: Equatable { case volume, brightness }

/// Où part le son : l'icône du volume change selon la sortie.
enum AudioOutput: Equatable {
    case speaker, headphones, airpods, airpodsPro, airpodsMax
}

struct HUDValue: Equatable {
    var kind: HUDKind
    var level: Float
    var muted: Bool = false
    var output: AudioOutput = .speaker
}

/// Affiche le volume et la luminosité quand l'utilisateur les change.
/// La luminosité n'est lue qu'après un appui sur une touche : les réglages automatiques
/// de macOS (capteur de lumière, économie d'énergie) ne déclenchent donc rien.
@MainActor
final class HUDManager: ObservableObject {
    static let shared = HUDManager()

    @Published private(set) var current: HUDValue?

    private var hideWork: DispatchWorkItem?
    private var tap: CFMachPort?
    private var tapRetry: Timer?
    private var outputDevice = AudioDeviceID(0)
    private var lastVolume: Float?

    func start() {
        installKeyTap()
        observeOutputDevice()
    }

    // MARK: - Affichage

    private func show(_ value: HUDValue) {
        guard Appearance.bool(Appearance.hudActivityKey) else { return }
        current = value
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.current = nil }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    private func showVolume() {
        guard let volume = Self.volume(of: outputDevice) else { return }
        show(HUDValue(kind: .volume, level: volume, muted: Self.isMuted(outputDevice), output: Self.output(of: outputDevice)))
    }

    private func showBrightness() {
        guard let brightness = Brightness.get() else { return }
        show(HUDValue(kind: .brightness, level: brightness))
    }

    // MARK: - Touches multimédia

    /// Avec l'autorisation Accessibilité, les touches sont interceptées et Pastille applique
    /// elle-même le changement : l'indicateur d'Apple ne s'affiche plus.
    /// Sans elle, on écoute seulement (Surveillance de l'entrée) et les deux indicateurs coexistent.
    private var intercepts = false
    private var askedAccessibility = false
    private var lastBrightnessStep: (key: MediaKey, source: MediaKey.Source, at: Date)?

    private func installKeyTap() {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): !askedAccessibility] as CFDictionary
        )
        askedAccessibility = true
        guard tap == nil || (trusted && !intercepts) else { return }
        if !trusted, !CGPreflightListenEventAccess() {
            CGRequestListenEventAccess()
        }

        let mask = CGEventMask(1 << 14)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async { MainActor.assumeIsolated { HUDManager.shared.reenableTap() } }
                return Unmanaged.passUnretained(event)
            }
            guard let press = MediaKey.Press(event: event, type: type) else {
                return Unmanaged.passUnretained(event)
            }
            // Le rappel tourne sur la boucle principale.
            let consumed = MainActor.assumeIsolated { HUDManager.shared.handle(press, flags: event.flags) }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: trusted ? .defaultTap : .listenOnly,
            eventsOfInterest: mask, callback: callback, userInfo: nil
        ) else {
            scheduleTapRetry()
            return
        }
        if let old = tap { CGEvent.tapEnable(tap: old, enable: false); CFMachPortInvalidate(old) }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        intercepts = trusted
        if trusted {
            tapRetry?.invalidate()
            tapRetry = nil
        } else {
            // On repasse en mode interception dès que l'Accessibilité est accordée.
            scheduleTapRetry()
        }
    }

    private func scheduleTapRetry() {
        guard tapRetry == nil else { return }
        tapRetry = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated { HUDManager.shared.installKeyTap() }
        }
    }

    private func reenableTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Renvoie true si l'événement est absorbé (macOS ne le verra pas).
    private func handle(_ press: MediaKey.Press, flags: CGEventFlags) -> Bool {
        // Activité désactivée dans les réglages : macOS reprend la main avec son propre indicateur.
        guard Appearance.bool(Appearance.hudActivityKey) else { return false }
        guard intercepts else {
            if press.isDown {
                // On laisse macOS appliquer le changement avant de lire la nouvelle valeur.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    MainActor.assumeIsolated { HUDManager.shared.showLevel(for: press.key) }
                }
            }
            return false
        }
        // Option + Maj : pas fin, comme macOS.
        let step: Float = flags.contains([.maskAlternate, .maskShift]) ? 1 / 64 : 1 / 16

        switch press.key {
        case .volumeUp, .volumeDown, .mute:
            guard Self.canSetVolume(outputDevice) else { return false }
            if press.isDown { stepVolume(press.key, by: step) }
            return true
        case .brightnessUp, .brightnessDown:
            guard Brightness.canSet else { return false }
            if press.isDown {
                // Certains claviers envoient la touche sous deux formes : un seul pas.
                if let last = lastBrightnessStep, last.key == press.key,
                   press.source != last.source, Date().timeIntervalSince(last.at) < 0.05 {
                    return true
                }
                lastBrightnessStep = (press.key, press.source, Date())
                stepBrightness(press.key, by: step)
            }
            return true
        }
    }

    private func showLevel(for key: MediaKey) {
        switch key {
        case .volumeUp, .volumeDown, .mute: showVolume()
        case .brightnessUp, .brightnessDown: showBrightness()
        }
    }

    private func stepVolume(_ key: MediaKey, by step: Float) {
        let device = outputDevice
        let current = Self.volume(of: device) ?? 0
        switch key {
        case .mute:
            Self.setMuted(device, !Self.isMuted(device))
        case .volumeUp:
            Self.setMuted(device, false)
            Self.setVolume(device, Self.snap(current + step, step))
        case .volumeDown:
            let new = Self.snap(current - step, step)
            Self.setVolume(device, new)
            if new == 0 { Self.setMuted(device, true) }
        default:
            break
        }
        lastVolume = Self.volume(of: device)
        showVolume()
    }

    private func stepBrightness(_ key: MediaKey, by step: Float) {
        guard let current = Brightness.get() else { return }
        let delta = key == .brightnessUp ? step : -step
        Brightness.set(Self.snap(current + delta, step))
        showBrightness()
    }

    /// Arrondit au cran le plus proche, entre 0 et 1.
    nonisolated static func snap(_ value: Float, _ step: Float) -> Float {
        min(max((value / step).rounded() * step, 0), 1)
    }

    // MARK: - Volume (CoreAudio)

    /// Suit aussi le curseur du Centre de contrôle, qui ne passe pas par les touches.
    private func observeOutputDevice() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
            MainActor.assumeIsolated { HUDManager.shared.attachToOutputDevice() }
        }
        attachToOutputDevice()
    }

    private func attachToOutputDevice() {
        outputDevice = Self.defaultOutputDevice()
        lastVolume = Self.volume(of: outputDevice)
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            let device = outputDevice
            AudioObjectAddPropertyListenerBlock(device, &address, .main) { _, _ in
                MainActor.assumeIsolated {
                    let manager = HUDManager.shared
                    guard device == manager.outputDevice else { return }
                    let volume = Self.volume(of: device)
                    if selector == kAudioDevicePropertyMute || volume != manager.lastVolume {
                        manager.lastVolume = volume
                        manager.showVolume()
                    }
                }
            }
        }
    }

    /// Casque Bluetooth (AirPods reconnus par leur nom), casque filaire, ou haut-parleurs.
    nonisolated private static func output(of device: AudioDeviceID) -> AudioOutput {
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)

        if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE {
            let name = deviceName(device).lowercased()
            if name.contains("airpods max") { return .airpodsMax }
            if name.contains("airpods pro") { return .airpodsPro }
            if name.contains("airpods") { return .airpods }
            return .headphones
        }
        // Prise casque du Mac : même appareil, mais la source de données passe à « casque » ('hdpn').
        var source = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &source) == noErr, source == 0x6864_706E {
            return .headphones
        }
        return .speaker
    }

    nonisolated private static func deviceName(_ device: AudioDeviceID) -> String {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() else { return "" }
        return value as String
    }

    nonisolated private static func defaultOutputDevice() -> AudioDeviceID {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    nonisolated private static func volume(of device: AudioDeviceID) -> Float? {
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        return status == noErr ? volume : nil
    }

    nonisolated private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    nonisolated private static func canSetVolume(_ device: AudioDeviceID) -> Bool {
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    nonisolated private static func setVolume(_ device: AudioDeviceID, _ value: Float) {
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var volume = Float32(value)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
    }

    nonisolated private static func setMuted(_ device: AudioDeviceID, _ muted: Bool) {
        var address = address(kAudioDevicePropertyMute)
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    nonisolated private static func isMuted(_ device: AudioDeviceID) -> Bool {
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        return muted != 0
    }
}

extension HUDManager {
    /// La luminosité de l'écran intégré est-elle pilotable (framework système non public) ?
    nonisolated static var brightnessControlAvailable: Bool { Brightness.canSet }
}

/// Touches son / luminosité, sous forme d'événements système (NX_SYSDEFINED)
/// ou de touches F dédiées selon le clavier.
private enum MediaKey: Equatable {
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown

    enum Source { case system, keyCode }

    struct Press {
        var key: MediaKey
        var isDown: Bool
        var source: Source

        init?(event: CGEvent, type: CGEventType) {
            if type == .keyDown || type == .keyUp {
                switch event.getIntegerValueField(.keyboardEventKeycode) {
                case 144: key = .brightnessUp
                case 145: key = .brightnessDown
                default: return nil
                }
                isDown = type == .keyDown
                source = .keyCode
                return
            }
            guard type.rawValue == 14,
                  let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return nil }
            let code = (ns.data1 & 0xFFFF_0000) >> 16
            let state = (ns.data1 & 0xFF00) >> 8
            guard state == 0xA || state == 0xB else { return nil }
            switch code {
            case 0: key = .volumeUp
            case 1: key = .volumeDown
            case 7: key = .mute
            case 2: key = .brightnessUp
            case 3: key = .brightnessDown
            default: return nil
            }
            isDown = state == 0xA
            source = .system
        }
    }
}

/// Luminosité de l'écran intégré via DisplayServices (framework système non public).
private enum Brightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    private static let getFn: GetFn? = {
        guard let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: GetFn.self)
    }()

    private static let setFn: SetFn? = {
        guard let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(sym, to: SetFn.self)
    }()

    /// Seulement l'écran intégré : sur un écran externe, on laisse macOS faire.
    static var canSet: Bool {
        setFn != nil && get() != nil && CGDisplayIsBuiltin(builtInDisplay()) != 0
    }

    static func set(_ value: Float) {
        _ = setFn?(builtInDisplay(), value)
    }

    static func get() -> Float? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(builtInDisplay(), &value) == 0 ? value : nil
    }

    private static func builtInDisplay() -> CGDirectDisplayID {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetActiveDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }
}

