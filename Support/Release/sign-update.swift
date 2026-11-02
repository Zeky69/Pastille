// Signature des mises à jour de Pastille (Ed25519).
//   swift sign-update.swift public-key        affiche la clé publique (à mettre dans Info.plist)
//   swift sign-update.swift sign <archive>    écrit <archive>.sig
// La clé privée est créée au premier usage dans ~/.config/pastille/update-signing-key : elle ne doit
// jamais quitter ce Mac ni entrer dans le dépôt. Garde-en une copie : sans elle, les Pastille déjà
// installées refuseront les prochaines mises à jour.
import CryptoKit
import Foundation

let keyFile = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/pastille/update-signing-key")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("❌ \(message)\n".utf8))
    exit(1)
}

func privateKey() -> Curve25519.Signing.PrivateKey {
    if let text = try? String(contentsOf: keyFile, encoding: .utf8),
       let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
        guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("clé illisible : \(keyFile.path)") }
        return key
    }
    let key = Curve25519.Signing.PrivateKey()
    do {
        try FileManager.default.createDirectory(at: keyFile.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: keyFile, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
    } catch {
        fail("impossible d'enregistrer la clé : \(error.localizedDescription)")
    }
    FileHandle.standardError.write(Data("🔑 Nouvelle clé de signature : \(keyFile.path) (garde-en une copie)\n".utf8))
    return key
}

let arguments = CommandLine.arguments.dropFirst()
switch (arguments.first, arguments.dropFirst().first) {
case ("public-key", _):
    print(privateKey().publicKey.rawRepresentation.base64EncodedString())
case ("sign", let path?):
    let archive = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: archive) else { fail("archive introuvable : \(path)") }
    let signature = try privateKey().signature(for: data)
    try Data(signature.base64EncodedString().utf8).write(to: archive.appendingPathExtension("sig"))
    print(archive.appendingPathExtension("sig").path)
default:
    fail("usage : sign-update.swift public-key | sign <archive>")
}
