import Foundation
import Testing
@testable import Pastille

/// Repérage des codes de vérification dans les SMS, iMessage et mails.
@Suite struct VerificationCodeTests {
    @Test(arguments: [
        ("Votre code de vérification est 482913.", "482913"),
        ("Instagram : utilisez le code 123 456 pour vous connecter", "123456"),
        ("Your verification code is 123-456", "123456"),
        ("G-582014 est votre code de validation Google.", "582014"),
        ("Code : 4821", "4821"),
        ("Your Uber code is 7731. Never share this code.", "7731"),
        ("Login code: 90817263", "90817263"),
        // Plusieurs nombres : les 6 chiffres l'emportent.
        ("Code 2026 pour la connexion : 551203", "551203"),
        // Montants, dates et pourcentages écartés.
        ("Paiement de 1250 € validé. Code de sécurité : 774411", "774411"),
        ("Le 01/11/2026, votre code de connexion est 3390", "3390"),
    ])
    func findsTheCode(text: String, expected: String) {
        #expect(VerificationCodeManager.extractCode(from: text) == expected)
    }

    @Test(arguments: [
        // Pas de mot-clé : un simple nombre n'est pas un code.
        "Rendez-vous à 14h, appartement 4521",
        "Ton colis 88213 arrive demain",
        // Mot-clé, mais seulement des montants, des dates, un numéro de téléphone.
        "Code promo : -20 % sur votre commande de 1250 €",
        "Votre code expire le 12/11/2026",
        "Code : appelez le 0612345678",
        "",
    ])
    func ignoresTextsWithoutCode(text: String) {
        #expect(VerificationCodeManager.extractCode(from: text) == nil)
    }

    @Test func picksTheNewestMessageWithACode() {
        // Les messages arrivent du plus récent au plus ancien.
        let messages = [
            (text: "Merci pour ta réponse", value: "récent sans code"),
            (text: "Votre code est 222222", value: "nouveau code"),
            (text: "Votre code est 111111", value: "ancien code"),
        ]
        #expect(VerificationCodeManager.newestWithCode(messages) == "nouveau code")
        #expect(VerificationCodeManager.newestWithCode([(text: "Salut", value: 1)]) == nil)
    }

    @Test(arguments: [
        ("Votre code Instagram est 123456", "", "Instagram"),
        ("BNP : votre code est 123456", "", "BNP"),
        ("Code : 123456", "no-reply@accounts.google.com", "Google"),
        ("Code : 123456", "AMELI", "Ameli"),
        ("Code : 123456", "Service Client Fnac", "Service Client Fnac"),
    ])
    func guessesTheService(text: String, sender: String, expected: String) {
        #expect(VerificationCodeManager.serviceName(text: text, sender: sender) == expected)
    }

    @Test(arguments: [("Code : 123456", "+33612345678"), ("Code : 123456", "0612345678"), ("Code : 123456", "x@localhost")])
    func phoneNumbersGiveNoService(text: String, sender: String) {
        #expect(VerificationCodeManager.serviceName(text: text, sender: sender) == nil)
    }
}

/// Texte des messages récents, archivé par Messages (NSAttributedString en « typedstream »).
@Suite struct TypedStreamTests {
    /// Archive comme le fait Messages (NSArchiver, appelé dynamiquement car obsolète).
    private func archive(_ text: String) -> Data? {
        let selector = NSSelectorFromString("archivedDataWithRootObject:")
        guard let archiver = NSClassFromString("NSArchiver") as AnyObject?, archiver.responds(to: selector) else { return nil }
        return archiver.perform(selector, with: NSAttributedString(string: text))?.takeUnretainedValue() as? Data
    }

    @Test(arguments: [
        "Votre code est 123456",
        "Accents, émojis 🔐 et guillemets « »",
        String(repeating: "Long message. ", count: 40),       // longueur sur 2 octets
        String(repeating: "Très long. ", count: 7_000),       // longueur sur 4 octets
    ])
    func readsTheTextWithoutUnarchiving(text: String) throws {
        let data = try #require(archive(text))
        #expect(VerificationCodeManager.typedStreamText(data) == text)
    }

    @Test func rejectsTruncatedOrForeignData() throws {
        let data = try #require(archive("Votre code est 123456"))
        // Coupé n'importe où : jamais de plantage, au pire rien.
        for end in stride(from: 0, to: data.count, by: 3) {
            _ = VerificationCodeManager.typedStreamText(data.prefix(end))
        }
        #expect(VerificationCodeManager.typedStreamText(Data("pas une archive".utf8)) == nil)
        #expect(VerificationCodeManager.typedStreamText(Data("NSString".utf8)) == nil)
        // Longueur annoncée bien plus grande que les données.
        #expect(VerificationCodeManager.typedStreamText(Data("NSString".utf8) + Data([1, 2, 3, 4, 5, 0x82, 0xFF, 0xFF, 0xFF, 0x7F, 65])) == nil)
        // Données tirées d'une tranche (indices qui ne commencent pas à 0).
        let slice = (Data("xxxx".utf8) + data).dropFirst(4)
        #expect(VerificationCodeManager.typedStreamText(slice) == "Votre code est 123456")
    }
}
