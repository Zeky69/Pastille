import Foundation

/// Journal des codes affichés, pour repérer les erreurs de détection.
/// Ne fait rien tant que le fichier ~/Library/Logs/Pastille/codes.log n'existe pas :
/// il faut le créer à la main sur son Mac, aucune autre installation n'écrit quoi que ce soit.
/// Le texte des messages reste dans ce fichier local, rien ne quitte le Mac.
enum CodeLog {
    static let file = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Pastille/codes.log")

    static func write(code: String, source: String, sender: String, text: String) {
        guard FileManager.default.fileExists(atPath: file.path),
              let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let entry = """
            [\(formatter.string(from: Date()))] \(source) — code affiché : \(code) — de : \(sender)
                « \(excerpt(around: code, in: text)) »

            """
        handle.seekToEndOfFile()
        handle.write(Data(entry.utf8))
    }

    /// Le passage du texte autour du code (environ 150 caractères de chaque côté), sur une ligne.
    static func excerpt(around code: String, in text: String) -> String {
        let flat = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        // Code coupé (« 123 456 ») : on cherche sa première moitié.
        let found = flat.range(of: code) ?? flat.range(of: String(code.prefix(max(3, code.count / 2))))
        guard let found else { return String(flat.prefix(300)) }
        let start = flat.index(found.lowerBound, offsetBy: -150, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(found.upperBound, offsetBy: 150, limitedBy: flat.endIndex) ?? flat.endIndex
        return (start > flat.startIndex ? "…" : "") + flat[start..<end] + (end < flat.endIndex ? "…" : "")
    }
}
