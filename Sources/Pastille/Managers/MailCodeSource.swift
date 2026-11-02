import Foundation
import SQLite3

/// Codes de vérification reçus par mail dans l'app Mail.
/// Lit la base de Mail (« Envelope Index ») puis, si besoin, le fichier .emlx du message.
/// Utilisé uniquement depuis la file de `VerificationCodeManager`.
final class MailCodeSource: @unchecked Sendable {
    struct Found {
        var code: String
        var sender: String
        var date: Date
    }

    private let root: URL? = {
        let mail = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Mail")
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: mail.path)) ?? [])
            .filter { $0.hasPrefix("V") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return versions.last.map { mail.appending(path: $0) }
    }()

    var walFile: URL? { root?.appending(path: "MailData/Envelope Index-wal") }

    private var startRowID: Int64?
    /// Mails déjà examinés (code trouvé ou corps lu sans code).
    private var handled: Set<Int64> = []
    /// Dossiers « Messages » où Mail range les .emlx, mis en cache.
    private var messageFolders: [URL] = []
    private var foldersScannedAt: Date?

    /// Mails récents (10 min) : un mail arrivé sans corps téléchargé est réessayé.
    private static let window: TimeInterval = 600

    /// Option coupée : au retour, on repartira du dernier mail existant.
    func reset() {
        startRowID = nil
        handled.removeAll()
    }

    func check() -> Found? {
        guard let root else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(root.appending(path: "MailData/Envelope Index").path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        // Premier passage : on part du dernier mail existant.
        guard let startRowID else {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT MAX(ROWID) FROM messages", -1, &statement, nil) == SQLITE_OK,
               sqlite3_step(statement) == SQLITE_ROW {
                startRowID = sqlite3_column_int64(statement, 0)
            }
            sqlite3_finalize(statement)
            return nil
        }

        let sql = """
            SELECT m.ROWID, COALESCE(s.subject, ''), COALESCE(su.summary, ''),
                   COALESCE(NULLIF(a.comment, ''), a.address, ''), m.date_received
            FROM messages m
            LEFT JOIN subjects s ON s.ROWID = m.subject
            LEFT JOIN summaries su ON su.ROWID = m.summary
            LEFT JOIN addresses a ON a.ROWID = m.sender
            WHERE m.ROWID > ? AND m.deleted = 0 AND m.date_received > ?
            ORDER BY m.ROWID DESC LIMIT 20
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, startRowID)
        sqlite3_bind_int64(statement, 2, Int64(Date().timeIntervalSince1970 - Self.window))

        var found: Found?
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            guard !handled.contains(id) else { continue }
            func text(_ column: Int32) -> String { sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
            let subject = text(1)
            let summary = text(2)
            let sender = text(3)
            let date = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 4)))

            // L'objet suffit souvent (« Votre code : 123456 ») ; sinon on lit le corps du mail.
            var code = VerificationCodeManager.extractCode(from: subject + "\n" + summary)
            if code == nil {
                guard let body = body(of: id) else { continue }  // pas encore téléchargé : on réessaiera
                code = VerificationCodeManager.extractCode(from: subject + "\n" + body)
            }
            handled.insert(id)
            if found == nil, let code {
                found = Found(code: code, sender: sender, date: date)
            }
        }
        return found
    }

    // MARK: - Fichier .emlx

    private func body(of id: Int64) -> String? {
        if let file = emlxFile(for: id) ?? rescanFolders().flatMap({ _ in emlxFile(for: id) }),
           let data = try? Data(contentsOf: file) {
            return MIME.text(ofEMLX: data)
        }
        return nil
    }

    private func emlxFile(for id: Int64) -> URL? {
        for folder in messageFolders {
            for name in ["\(id).emlx", "\(id).partial.emlx"] {
                let file = folder.appending(path: name)
                if FileManager.default.fileExists(atPath: file.path) { return file }
            }
        }
        return nil
    }

    /// Recense les dossiers « Messages » (sans parcourir les mails eux-mêmes), au plus toutes les 30 s.
    private func rescanFolders() -> Void? {
        guard let root else { return nil }
        if let foldersScannedAt, Date().timeIntervalSince(foldersScannedAt) < 30 { return nil }
        foldersScannedAt = Date()
        var folders: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            switch url.lastPathComponent {
            case "Messages":
                folders.append(url)
                enumerator?.skipDescendants()
            case "Attachments", "MailData":
                enumerator?.skipDescendants()
            default:
                break
            }
        }
        messageFolders = folders
        return ()
    }
}

/// Extraction minimale du texte d'un mail : parties text/plain (ou HTML nettoyé),
/// décodage base64 / quoted-printable, multipart imbriqués.
enum MIME {
    static func text(ofEMLX data: Data) -> String? {
        // Un .emlx commence par la taille du message sur une ligne, puis le message brut.
        guard let newline = data.firstIndex(of: 0x0A),
              let length = Int(String(decoding: data[..<newline], as: UTF8.self).trimmingCharacters(in: .whitespaces))
        else { return nil }
        let start = data.index(after: newline)
        let message = data[start..<min(data.count, start + length)]
        return text(ofPart: Data(message))
    }

    private static func text(ofPart part: Data) -> String? {
        let raw = String(decoding: part, as: UTF8.self)
        let (headers, body) = split(raw)
        let contentType = header("content-type", in: headers).lowercased()

        if contentType.hasPrefix("multipart/"), let boundary = parameter("boundary", in: header("content-type", in: headers)) {
            let parts = body.components(separatedBy: "--" + boundary).dropFirst().filter { !$0.hasPrefix("--") }
            let texts = parts.compactMap { text(ofPart: Data($0.utf8)) }
            return texts.first { !$0.isEmpty }
        }
        guard contentType.isEmpty || contentType.hasPrefix("text/") else { return nil }

        let encoding = header("content-transfer-encoding", in: headers).lowercased()
        let charset = parameter("charset", in: header("content-type", in: headers))?.lowercased() ?? "utf-8"
        var decoded: String
        switch encoding {
        case "base64":
            let data = Data(base64Encoded: body.filter { !$0.isWhitespace }, options: .ignoreUnknownCharacters) ?? Data()
            decoded = string(from: data, charset: charset)
        case "quoted-printable":
            decoded = string(from: quotedPrintable(body), charset: charset)
        default:
            decoded = body
        }
        if contentType.hasPrefix("text/html") { decoded = stripHTML(decoded) }
        return decoded
    }

    private static func split(_ raw: String) -> (headers: String, body: String) {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        guard let range = normalized.range(of: "\n\n") else { return (normalized, "") }
        return (String(normalized[..<range.lowerBound]), String(normalized[range.upperBound...]))
    }

    private static func header(_ name: String, in headers: String) -> String {
        // Les en-têtes peuvent continuer sur les lignes suivantes (indentées).
        let unfolded = headers.replacingOccurrences(of: "\n[ \t]+", with: " ", options: .regularExpression)
        for line in unfolded.components(separatedBy: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == name {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    private static func parameter(_ name: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: name + #"\s*=\s*"?([^";]+)"?"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }

    private static func quotedPrintable(_ text: String) -> Data {
        var bytes: [UInt8] = []
        let source = Array(text.replacingOccurrences(of: "=\n", with: "").utf8)
        var i = 0
        while i < source.count {
            if source[i] == UInt8(ascii: "="), i + 2 < source.count,
               let value = UInt8(String(decoding: source[i + 1...i + 2], as: UTF8.self), radix: 16) {
                bytes.append(value)
                i += 3
            } else {
                bytes.append(source[i])
                i += 1
            }
        }
        return Data(bytes)
    }

    private static func string(from data: Data, charset: String) -> String {
        if charset.contains("8859") || charset.contains("1252") || charset.contains("latin") {
            return String(data: data, encoding: .isoLatin1) ?? ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func stripHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "(?is)<(style|script)[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, value) in ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&#39;": "'", "&quot;": "\"", "&eacute;": "é", "&egrave;": "è", "&agrave;": "à"] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
