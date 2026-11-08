import Combine
import ServiceManagement
import SwiftUI

struct ActivitySettings: View {
    @AppStorage(Settings.musicLiveActivityKey) private var music = true
    @AppStorage(Appearance.clockActivityKey) private var clock = true
    @AppStorage(Appearance.downloadActivityKey) private var download = true
    @AppStorage(Appearance.codeActivityKey) private var code = true
    @AppStorage(Appearance.hudActivityKey) private var hud = true
    @AppStorage(Appearance.batteryAlertKey) private var battery = true
    @AppStorage(Appearance.deviceConnectedKey) private var deviceConnected = true
    @AppStorage(Appearance.powerKey) private var power = true
    @AppStorage(Appearance.codesMessagesKey) private var codesMessages = true
    @AppStorage(Appearance.codesMailKey) private var codesMail = true
    @AppStorage(Appearance.musicPriorityKey) private var musicPriority = true
    @AppStorage(Appearance.musicOtherAppsKey) private var musicOtherApps = true
    @AppStorage(Appearance.musicSourceBadgeKey) private var sourceBadge = true
    @AppStorage(Appearance.timerDoneKey) private var timerDone = true
    @AppStorage(Appearance.newTrackKey) private var newTrack = true
    @AppStorage(Appearance.newTrackManualOnlyKey) private var newTrackManualOnly = false
    @AppStorage(Appearance.codesSenderKey) private var codesSender = true
    @AppStorage(Appearance.recordingKey) private var recording = true
    @AppStorage(Appearance.focusKey) private var focus = true

    var body: some View {
        Form {
            Section {
                row("music.note", .pink, "Musique en cours", "Pochette et spectre de part et d'autre de l'encoche.", $music)
                row("timer", .orange, "Minuteur et chronomètre", "Ceux de l'app Horloge, en direct.", $clock)
                row("bell.fill", .orange, "Minuteur terminé", "L'anneau clignote avec « Terminé » quand il arrive à zéro.", $timerDone)
                row("arrow.down.circle.fill", .blue, "Téléchargements", "Anneau de progression puis coche verte.", $download)
                row("key.fill", .green, "Codes de vérification", "Reçus par SMS, iMessage ou Mail.", $code)
                row("speaker.wave.2.fill", .gray, "Volume et luminosité", "Remplace l'indicateur d'Apple (désactivé : celui d'Apple revient).", $hud)
                row("battery.25", .red, "Batterie faible", "Alerte à 20 %, 10 % et 5 %.", $battery)
                row("bolt.fill", .green, "Branchement et charge complète", "Éclair au branchement et au débranchement, « Chargé » à 100 %.", $power)
                row("headphones", .indigo, "Appareil connecté", "Casque, AirPods ou clavier qui se connecte, avec sa batterie.", $deviceConnected)
                row("record.circle", .red, "Enregistrement d'écran", "Point rouge et durée pendant un enregistrement ⌘⇧5. Stop dans la pastille ouverte.", $recording)
                row("moon.fill", .indigo, "Mode Concentration", "Annonce Ne pas déranger, Sommeil, Travail… quand il s'active ou se termine (accès complet au disque).", $focus)
            } header: {
                Text("Ce qui peut s'afficher dans la pastille fermée")
            }

            Section {
                row("music.quarternote.3", .pink, "Priorité à la musique", "Une vidéo ne s'affiche que si aucune musique ne joue.", $musicPriority)
                row("play.rectangle.fill", .red, "Son des autres apps", "YouTube dans le navigateur, vidéos, podcasts… (coupé : Musique, Spotify, Deezer… seulement).", $musicOtherApps)
                row("app.badge.fill", .gray, "Icône de l'app sur la pochette", "Pour savoir d'où vient le son.", $sourceBadge)
                row("music.note.list", .purple, "Nouveau morceau", "Pochette et titre 2 secondes dans la pastille fermée quand la chanson change.", $newTrack)
                row("forward.fill", .purple, "Seulement quand je change de morceau", "Avec « Suivant », « Précédent », les AirPods… Pas quand la chanson suivante s'enchaîne toute seule.", $newTrackManualOnly)
                    .disabled(!newTrack)
            } header: {
                Text("Musique")
            }

            Section {
                row("message.fill", .green, "Messages", "SMS et iMessages reçus sur le Mac.", $codesMessages)
                row("envelope.fill", .blue, "Mail", "Mails reçus dans l'app Mail.", $codesMail)
                row("person.text.rectangle", .gray, "Nom du service", "« Instagram · 482913 » quand l'expéditeur est reconnaissable.", $codesSender)
            } header: {
                Text("Où chercher les codes de vérification")
            }
            .disabled(!code)
        }
        .formStyle(.grouped)
    }

    private func row(_ symbol: String, _ color: Color, _ title: String, _ detail: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Autorisations
