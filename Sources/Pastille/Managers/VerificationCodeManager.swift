import AppKit
import SQLite3

/// Code de vérification reçu par SMS ou iMessage.
struct VerificationCode: Equatable {
    var code: String
    var sender: String
    var received: Date
    /// Service qui envoie le code (« Instagram », « Google »…), quand on arrive à le deviner.
    var service: String?
}

/// Repère les codes de vérification dans les messages reçus (base de Messages) et les mails (app Mail), lus en local.
/// Nécessite l'« Accès complet au disque » ; rien ne quitte le Mac.
@MainActor
final class VerificationCodeManager: ObservableObject {
    static let shared = VerificationCodeManager()

    @Published private(set) var current: VerificationCode?
    @Published private(set) var copied = false
    /// Le code s'affiche dans la pastille fermée seulement ses 5 premières secondes.
    @Published private(set) var showsInClosedPill = false
    private var closedPillWork: DispatchWorkItem?
    /// false tant que macOS refuse l'accès à la base de Messages.
    @Published private(set) var hasAccess = true

    private let messagesFolder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Messages")
    private var database: URL { messagesFolder.appending(path: "chat.db") }
    private var lastRowID: Int64?
    private var watcher: DispatchSourceFileSystemObject?
    private var mailWatcher: DispatchSourceFileSystemObject?
    private let mail = MailCodeSource()
    private var poll: Timer?
    private var expireWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "pastille.messages")

    /// Un code reste 5 s dans la pastille fermée, et 10 s en tout dans la pastille ouverte
    /// (en haut à gauche) ; 4 s après avoir été copié, il disparaît.
    private static let lifetime: TimeInterval = 10
    private static let closedPillDuration: TimeInterval = 5

    func start() {
        watch()
        // Filet de sécurité si l'écriture de Messages nous échappe ; réessaie aussi l'accès refusé.
        poll = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated {
                let manager = VerificationCodeManager.shared
                if manager.watcher == nil || manager.mailWatcher == nil { manager.watch() }
                manager.check()
            }
        }
        poll?.tolerance = 1
        check()
    }

    func copy() {
        guard let current else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(current.code, forType: .string)
        copied = true
        schedule(expireIn: 4)
    }

    func dismiss() {
        expireWork?.cancel()
        closedPillWork?.cancel()
        current = nil
        copied = false
        showsInClosedPill = false
    }

    // MARK: - Lecture

    /// Messages et Mail écrivent d'abord dans leur journal (-wal) : on le surveille pour réagir tout de suite.
    private func watch() {
        if watcher == nil {
            watcher = watchFile(messagesFolder.appending(path: "chat.db-wal")) { $0.watcher = nil }
        }
        if mailWatcher == nil, let wal = mail.walFile {
            mailWatcher = watchFile(wal) { $0.mailWatcher = nil }
        }
    }

    private func watchFile(_ url: URL, onReplaced: @escaping (VerificationCodeManager) -> Void) -> DispatchSourceFileSystemObject? {
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main
        )
        source.setEventHandler {
            MainActor.assumeIsolated {
                let manager = VerificationCodeManager.shared
                if !source.data.isDisjoint(with: [.delete, .rename]) {
                    source.cancel()
                    onReplaced(manager)
                }
                manager.check()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func check() {
        // Option coupée : on ne lit ni Messages ni Mail. Au retour, on repart du dernier message
        // existant plutôt que de ressortir ceux arrivés entre-temps.
        let codes = Appearance.bool(Appearance.codeActivityKey)
        let readsMessages = codes && Appearance.bool(Appearance.codesMessagesKey)
        let readsMail = codes && Appearance.bool(Appearance.codesMailKey)
        if !readsMessages { lastRowID = nil }
        let path = database.path
        let since = lastRowID
        let mail = mail
        queue.async {
            let result = readsMessages ? Self.readMessages(path: path, after: since) : nil
            if !readsMail { mail.reset() }
            let mailCode = readsMail ? mail.check() : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let manager = VerificationCodeManager.shared
                    if let result, readsMessages, manager.lastRowID == since { manager.apply(result) }
                    if let mailCode, Appearance.bool(Appearance.codesMailKey) {
                        manager.show(VerificationCode(
                            code: mailCode.code, sender: mailCode.sender, received: mailCode.date,
                            service: Self.serviceName(text: "", sender: mailCode.sender)
                        ))
                    }
                }
            }
        }
    }

    private func apply(_ result: ReadResult) {
        switch result {
        case .denied:
            if hasAccess { hasAccess = false }
        case let .messages(maxRowID, messages):
            if !hasAccess { hasAccess = true }
            // Premier passage : on part du dernier message existant, sans ressortir les anciens codes.
            let isFirstRead = lastRowID == nil
            lastRowID = max(lastRowID ?? 0, maxRowID)
            // Plusieurs codes arrivés d'un coup : le plus récent est le bon.
            guard !isFirstRead, let message = Self.newestWithCode(messages.map { ($0.text, $0) }),
                  let code = Self.extractCode(from: message.text) else { return }
            show(VerificationCode(
                code: code, sender: message.sender, received: message.date,
                service: Self.serviceName(text: message.text, sender: message.sender)
            ))
        }
    }

    /// Premier élément (le plus récent) dont le texte contient un code.
    nonisolated static func newestWithCode<T>(_ items: [(text: String, value: T)]) -> T? {
        items.first { extractCode(from: $0.text) != nil }?.value
    }

    private func show(_ code: VerificationCode) {
        current = code
        copied = false
        showsInClosedPill = true
        closedPillWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.showsInClosedPill = false }
        closedPillWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closedPillDuration, execute: work)
        schedule(expireIn: Self.lifetime)
    }

    private func schedule(expireIn delay: TimeInterval) {
        expireWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        expireWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Base de Messages

    private struct Message {
        var text: String
        var sender: String
        var date: Date
    }

    private enum ReadResult {
        case denied
        case messages(maxRowID: Int64, [Message])
    }

    nonisolated private static func readMessages(path: String, after rowID: Int64?) -> ReadResult {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return .denied
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        // Messages reçus (pas envoyés), les plus récents d'abord. `date` est en nanosecondes depuis 2001.
        let sql = """
            SELECT m.ROWID, m.text, m.attributedBody, m.date, COALESCE(h.id, '')
            FROM message m LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE m.is_from_me = 0 AND m.ROWID > ?
            ORDER BY m.ROWID DESC LIMIT 20
            """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            // Lecture refusée (pas d'Accès complet au disque) : la base s'ouvre mais reste illisible.
            return .denied
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, rowID ?? Int64.max - 1)

        var messages: [Message] = []
        var maxRowID = rowID ?? 0
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            maxRowID = max(maxRowID, id)
            var text = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            if text.isEmpty, let blob = sqlite3_column_blob(statement, 2) {
                let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 2)))
                text = decodeAttributedBody(data) ?? ""
            }
            let nanoseconds = sqlite3_column_int64(statement, 3)
            let sender = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            messages.append(Message(
                text: text,
                sender: sender,
                date: Date(timeIntervalSinceReferenceDate: Double(nanoseconds) / 1_000_000_000)
            ))
        }

        // Au premier passage on ne lit rien (ROWID > max) : on récupère juste le dernier numéro.
        if rowID == nil {
            var maxStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT MAX(ROWID) FROM message", -1, &maxStatement, nil) == SQLITE_OK,
               sqlite3_step(maxStatement) == SQLITE_ROW {
                maxRowID = sqlite3_column_int64(maxStatement, 0)
            }
            sqlite3_finalize(maxStatement)
        }
        return .messages(maxRowID: maxRowID, messages)
    }

    /// Les messages récents gardent leur texte dans `attributedBody` (NSAttributedString archivé).
    nonisolated private static func decodeAttributedBody(_ data: Data) -> String? {
        // Le texte d'un message vient de n'importe qui : on le lit d'abord directement dans les octets,
        // sans recréer d'objets à partir de ces données.
        if let text = typedStreamText(data) { return text }
        // Format « typedstream » d'avant NSKeyedArchiver : seul NSUnarchiver (obsolète mais toujours
        // présent) sait le lire. Appel dynamique pour éviter l'avertissement de dépréciation.
        let selector = NSSelectorFromString("unarchiveObjectWithData:")
        if let unarchiver = NSClassFromString("NSUnarchiver") as AnyObject?,
           unarchiver.responds(to: selector),
           let string = (unarchiver.perform(selector, with: data)?.takeUnretainedValue() as? NSAttributedString)?.string {
            return string
        }
        return nil
    }

    /// Texte d'un NSAttributedString archivé en « typedstream » : il suit le marqueur « NSString »
    /// (puis 5 octets), précédé de sa longueur (1 octet, ou 0x81 + 2 octets, ou 0x82 + 4 octets).
    nonisolated static func typedStreamText(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard let marker = data.range(of: Data("NSString".utf8)) else { return nil }
        var i = marker.upperBound - data.startIndex + 5
        guard i < bytes.count else { return nil }
        var length = Int(bytes[i])
        i += 1
        if length == 0x81 {
            guard i + 2 <= bytes.count else { return nil }
            length = Int(bytes[i]) | Int(bytes[i + 1]) << 8
            i += 2
        } else if length == 0x82 {
            guard i + 4 <= bytes.count else { return nil }
            length = Int(bytes[i]) | Int(bytes[i + 1]) << 8 | Int(bytes[i + 2]) << 16 | Int(bytes[i + 3]) << 24
            i += 4
        }
        guard length >= 0, i + length <= bytes.count else { return nil }
        return String(bytes: bytes[i..<i + length], encoding: .utf8)
    }

    // MARK: - Nom du service

    /// Services courants, cherchés dans le texte du message.
    nonisolated private static let knownServices = [
        "Instagram", "WhatsApp", "Facebook", "Messenger", "Google", "Apple", "Microsoft", "Amazon", "PayPal",
        "Snapchat", "TikTok", "Discord", "Telegram", "Signal", "Twitter", "LinkedIn", "Netflix", "Spotify",
        "Uber", "Deliveroo", "Airbnb", "Steam", "Epic Games", "Riot", "Twitch", "Binance", "Revolut", "Lydia",
        "BNP", "Société Générale", "Crédit Agricole", "LCL", "Boursorama", "Caisse d'Épargne", "La Banque Postale",
        "Ameli", "Doctolib", "SNCF", "Orange", "SFR", "Bouygues", "Free", "Leboncoin", "Vinted", "Shein", "Yahoo",
    ]

    /// Devine le service : nom connu dans le texte, « BNP : … » en début de message, nom d'affichage
    /// de l'expéditeur, ou domaine de son adresse mail. Un simple numéro ne donne rien.
    nonisolated static func serviceName(text: String, sender: String) -> String? {
        let lowered = text.lowercased()
        if let known = knownServices.first(where: { lowered.contains($0.lowercased()) }) { return known }

        if let regex = try? NSRegularExpression(pattern: #"^\s*([A-Z][A-Za-z0-9&'.]+(?: [A-Z][A-Za-z0-9&'.]+)?)\s*[:\-–]"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text),
           !["code", "votre", "ton", "your", "bonjour", "hello", "hi", "otp", "pin", "info", "alerte"]
               .contains(text[range].lowercased().split(separator: " ").first.map(String.init) ?? "") {
            return String(text[range])
        }

        let trimmed = sender.trimmingCharacters(in: .whitespaces)
        if let at = trimmed.firstIndex(of: "@") {
            // no-reply@accounts.google.com → Google
            let parts = trimmed[trimmed.index(after: at)...].split(separator: ".")
            guard parts.count >= 2 else { return nil }
            return parts[parts.count - 2].capitalized
        }
        // Expéditeur alphanumérique (« INSTAGRAM ») ou nom d'affichage d'un mail ; un numéro ne dit rien.
        guard trimmed.contains(where: \.isLetter), !trimmed.hasPrefix("+") else { return nil }
        return trimmed == trimmed.uppercased() ? trimmed.capitalized : trimmed
    }

    // MARK: - Détection du code

    nonisolated private static let keywords = [
        "code", "vérification", "verification", "verify", "otp", "authentif",
        "authentication", "connexion", "login", "sign in", "sécurité", "security", "passcode",
        "pin", "2fa", "mot de passe", "password", "validation", "valider",
    ]

    /// Un code de 4 à 8 chiffres (ou « 123-456 », « 123 456 », « G-123456 ») dans un message qui en parle.
    nonisolated static func extractCode(from text: String) -> String? {
        let lowered = text.lowercased()
        guard keywords.contains(where: lowered.contains) else { return nil }

        let range = NSRange(text.startIndex..., in: text)
        func matches(_ pattern: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
        }
        // « 123-456 » ou « 123 456 » → « 123456 ».
        if let split = matches(#"(?<![\d€$£,./])(?<![€$£] )\d{3}[- ]\d{3}(?! ?[\d€$£/])"#).first {
            return split.filter(\.isNumber)
        }
        // Les montants (« 1250 € ») et les dates (« 01/11/2026 ») sont écartés.
        // Plusieurs nombres : on préfère 6 chiffres (le format le plus courant), sinon le premier.
        let numbers = matches(#"(?<![\d€$£,./#])(?<![€$£] )\d{4,8}(?! ?[€$£%]|[\d/]|[,.]\d)"#)
        if let code = numbers.first(where: { $0.count == 6 }) ?? numbers.first { return code }
        // « G-123456 » (Google) reste tel quel.
        return matches(#"\b[A-Z0-9]{1,4}-\d{4,8}\b"#).first
    }
}
