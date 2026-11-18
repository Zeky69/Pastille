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
        ("482913 est votre code de vérification", "482913"),
        ("Your one-time passcode: 662190", "662190"),
        ("Votre code\u{00A0}: 913 004", "913004"),
        // Mail : le code au milieu d'un pied de page plein de nombres.
        ("Your security code is 123456. Copyright 2026 Microsoft, 1 Microsoft Way, Redmond, WA 98052", "123456"),
        ("Bonjour Jean, merci de votre inscription. Votre code de vérification : 552901 Ce code expire dans 10 minutes. © 2026 Acme, 12 rue de Paris 75002 Paris", "552901"),
        ("Commande n° 773120 – votre code de retrait est 4417", "4417"),
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
        // Années, codes promo, codes postaux, références : jamais un code.
        "Newsletter de novembre 2026 : découvrez nos offres, code promo NOEL",
        "Black Friday : -30 % avec le code BLACK2026 jusqu'au 30/11",
        "Utilisez le code promo 4821 pour 10 % de réduction",
        "Votre code postal : 75011",
        "Votre commande n° 482913 est confirmée. Code de suivi disponible demain.",
        "Facture 2026-11 : 1250 EUR. Pour toute question, code client 88231",
        "© 2026 Apple Inc. Si vous avez une question sur le code de la route",
        "Réunion le 18 novembre 2026 à 14:30, pensez à votre code d'accès",
        "Code : 2026",
        "Votre code de vérification expirera en 2026",
        "Bonjour, vous avez reçu 1500 points. Le code avantage vous attend sur l'appli",
        "Merci pour votre commande #123456 ! Profitez du code SAVE10",
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

/// Le code s'affiche coupé en deux, pour se lire d'un coup d'œil.
@Suite struct SpacedCodeTests {
    @Test(arguments: [
        ("482913", "482 913"),
        ("12345678", "1234 5678"),
        ("A1B2C3", "A1B 2C3"),
        ("1234", "1234"),      // trop court : tel quel
        ("12345", "12345"),
        ("1234567", "1234567"), // impair : on ne sait pas où couper
    ])
    func splitsInTheMiddle(code: String, shown: String) {
        #expect(VerificationCode.spaced(code) == shown)
    }
}
