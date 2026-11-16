import Foundation
import Testing
@testable import Pastille

/// Repérage des appels : quelle app, quand l'appel commence, quand il se termine.
@Suite struct CallDetectionTests {
    private func client(_ id: String?, name: String? = nil, input: Bool = true, output: Bool = true) -> AudioClient {
        AudioClient(bundleID: id, processName: name, usesInput: input, usesOutput: output)
    }

    @Test func recognizesCallApps() {
        // FaceTime (et les appels téléphone via l'iPhone) : le son passe par un service de macOS.
        #expect(CallDetector.app(for: client(nil, name: "avconferenced")) == CallApp(bundleID: "com.apple.FaceTime", isBrowser: false))
        #expect(CallDetector.app(for: client("com.apple.FaceTime"))?.bundleID == "com.apple.FaceTime")
        // Le son de Discord passe par un processus d'aide ; les versions PTB et Canary comptent aussi.
        #expect(CallDetector.app(for: client("com.hnc.Discord.helper.Renderer"))?.bundleID == "com.hnc.Discord")
        #expect(CallDetector.app(for: client("com.hnc.DiscordPTB"))?.bundleID == "com.hnc.Discord")
        // WhatsApp, nouvelle et ancienne app.
        #expect(CallDetector.app(for: client("net.whatsapp.WhatsApp"))?.bundleID == "net.whatsapp.WhatsApp")
        #expect(CallDetector.app(for: client("desktop.WhatsApp"))?.bundleID == "net.whatsapp.WhatsApp")
        #expect(CallDetector.app(for: client("us.zoom.xos"))?.bundleID == "us.zoom.xos")
    }

    @Test func browsersAreFlagged() {
        let chrome = CallDetector.app(for: client("com.google.Chrome.helper"))
        #expect(chrome == CallApp(bundleID: "com.google.Chrome", isBrowser: true))
        #expect(CallDetector.app(for: client("com.apple.WebKit.GPU")) == CallApp(bundleID: "com.apple.Safari", isBrowser: true))
    }

    @Test func otherMicUsersAreNotCalls() {
        for id in ["com.apple.VoiceMemos", "com.apple.SpeechRecognitionCore.speechrecognitiond", "com.apple.QuickTimePlayerX",
                   "com.spotify.client", "com.obsproject.obs-studio"] {
            #expect(CallDetector.app(for: client(id)) == nil, "\(id)")
        }
        #expect(CallDetector.app(for: client(nil, name: "coreaudiod")) == nil)
    }
}

@Suite struct CallTrackerTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private let discordTalking = AudioClient(bundleID: "com.hnc.Discord.helper", usesInput: true, usesOutput: true)
    private let discordListening = AudioClient(bundleID: "com.hnc.Discord.helper", usesInput: false, usesOutput: true)
    private let chromeTalking = AudioClient(bundleID: "com.google.Chrome.helper", usesInput: true, usesOutput: true)
    private let chromePlaying = AudioClient(bundleID: "com.google.Chrome.helper", usesInput: false, usesOutput: true)

    @Test func callStartsAfterTheMicStaysOn() {
        var tracker = CallTracker()
        #expect(tracker.update([discordTalking], at: at(0)) == nil)
        #expect(tracker.update([discordTalking], at: at(1)) == nil)
        let change = tracker.update([discordTalking], at: at(2))
        // La durée compte depuis l'ouverture du micro, pas depuis la confirmation.
        let call = CallTracker.Call(app: CallApp(bundleID: "com.hnc.Discord", isBrowser: false), startedAt: at(0))
        #expect(change == .started(call))
        #expect(tracker.call == call)
    }

    @Test func briefMicUseIsNotACall() {
        var tracker = CallTracker()
        _ = tracker.update([discordTalking], at: at(0))
        _ = tracker.update([], at: at(1))
        // Le micro se rallume : le compte repart de zéro.
        _ = tracker.update([discordTalking], at: at(1.5))
        #expect(tracker.update([discordTalking], at: at(2.5)) == nil)
        #expect(tracker.call == nil)
    }

    @Test func soundWithoutMicNeverStartsACall() {
        var tracker = CallTracker()
        for second in 0..<10 { _ = tracker.update([discordListening, chromePlaying], at: at(Double(second))) }
        #expect(tracker.call == nil)
    }

    @Test func muteInTheAppKeepsTheCall() {
        var tracker = CallTracker()
        _ = tracker.update([discordTalking], at: at(0))
        _ = tracker.update([discordTalking], at: at(2))
        // Sourdine dans l'app : le micro se ferme, mais l'app joue toujours le son de l'appel.
        for second in 3...30 { #expect(tracker.update([discordListening], at: at(Double(second))) == nil) }
        #expect(tracker.call != nil)
    }

    @Test func callEndsAfterSilence() {
        var tracker = CallTracker()
        _ = tracker.update([discordTalking], at: at(0))
        _ = tracker.update([discordTalking], at: at(2))
        #expect(tracker.update([], at: at(10)) == nil)
        #expect(tracker.update([], at: at(12)) == nil)
        // Un sursaut (l'app relâche le son un instant) ne coupe pas l'appel.
        #expect(tracker.update([discordTalking], at: at(12.5)) == nil)
        #expect(tracker.update([], at: at(13)) == nil)
        #expect(tracker.update([], at: at(15)) == nil)
        guard case .ended(let ended)? = tracker.update([], at: at(16)) else {
            Issue.record("L'appel aurait dû se terminer")
            return
        }
        #expect(ended.startedAt == at(0))
        #expect(tracker.call == nil)
    }

    @Test func browserCallEndsEvenIfAVideoKeepsPlaying() {
        var tracker = CallTracker()
        _ = tracker.update([chromeTalking], at: at(0))
        #expect(tracker.update([chromeTalking], at: at(2)) != nil)
        // Fin de la visio dans le navigateur ; une vidéo continue de jouer dans un autre onglet.
        _ = tracker.update([chromePlaying], at: at(3))
        guard case .ended? = tracker.update([chromePlaying], at: at(6)) else {
            Issue.record("L'appel dans le navigateur aurait dû se terminer")
            return
        }
    }

    @Test func faceTimeCallThroughTheSystemService() {
        var tracker = CallTracker()
        let faceTime = AudioClient(bundleID: nil, processName: "avconferenced", usesInput: true, usesOutput: true)
        _ = tracker.update([faceTime], at: at(0))
        #expect(tracker.update([faceTime], at: at(2)) == .started(.init(app: CallApp(bundleID: "com.apple.FaceTime", isBrowser: false), startedAt: at(0))))
    }

    @Test func voiceMemoWhileListeningToMusicIsNotACall() {
        var tracker = CallTracker()
        let memo = AudioClient(bundleID: "com.apple.VoiceMemos", usesInput: true, usesOutput: false)
        let music = AudioClient(bundleID: "com.apple.Music", usesInput: false, usesOutput: true)
        for second in 0..<10 { _ = tracker.update([memo, music], at: at(Double(second))) }
        #expect(tracker.call == nil)
    }
}
