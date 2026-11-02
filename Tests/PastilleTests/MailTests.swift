import Foundation
import Testing
@testable import Pastille

/// Lecture du corps des mails (.emlx de l'app Mail).
@Suite struct MailTests {
    /// Un .emlx : la taille du message sur la première ligne, puis le message brut.
    private func emlx(_ message: String) -> Data {
        let body = Data(message.replacingOccurrences(of: "\n", with: "\r\n").utf8)
        return Data("\(body.count)\n".utf8) + body + Data("<?xml version=\"1.0\"?><plist/>".utf8)
    }

    @Test func plainText() {
        let data = emlx("Subject: Code\nContent-Type: text/plain; charset=utf-8\n\nVotre code est 123456")
        #expect(MIME.text(ofEMLX: data) == "Votre code est 123456")
    }

    @Test func base64() {
        let encoded = Data("Votre code de vérification : 654321".utf8).base64EncodedString(options: .lineLength64Characters)
        let data = emlx("Content-Type: text/plain; charset=\"UTF-8\"\nContent-Transfer-Encoding: base64\n\n\(encoded)")
        #expect(MIME.text(ofEMLX: data) == "Votre code de vérification : 654321")
    }

    @Test func quotedPrintable() {
        let data = emlx("Content-Type: text/plain; charset=utf-8\nContent-Transfer-Encoding: quoted-printable\n\nV=C3=A9rification =\nr=C3=A9ussie : 112233")
        #expect(MIME.text(ofEMLX: data) == "Vérification réussie : 112233")
    }

    @Test func latin1() {
        let latin = String(data: Data("Vérification".utf8), encoding: .utf8)!
        let encoded = latin.data(using: .isoLatin1)!.base64EncodedString()
        let data = emlx("Content-Type: text/plain; charset=iso-8859-1\nContent-Transfer-Encoding: base64\n\n\(encoded)")
        #expect(MIME.text(ofEMLX: data) == "Vérification")
    }

    @Test func htmlIsStripped() {
        let html = "<html><style>.c{color:#123456}</style><body><p>Votre code&nbsp;:</p><td>778899</td></body></html>"
        let data = emlx("Content-Type: text/html; charset=utf-8\n\n\(html)")
        let text = MIME.text(ofEMLX: data) ?? ""
        #expect(!text.contains("<"))
        #expect(!text.contains("123456"))  // la couleur du style ne doit pas passer pour un code
        #expect(VerificationCodeManager.extractCode(from: text) == "778899")
    }

    @Test func nestedMultipart() {
        let message = """
        Content-Type: multipart/mixed; boundary="outer"

        --outer
        Content-Type: multipart/alternative;
         boundary=inner

        --inner
        Content-Type: text/plain; charset=utf-8

        Code de connexion : 445566
        --inner
        Content-Type: text/html; charset=utf-8

        <p>Code de connexion : 445566</p>
        --inner--
        --outer
        Content-Type: image/png
        Content-Transfer-Encoding: base64

        iVBORw0KGgo=
        --outer--
        """
        let text = MIME.text(ofEMLX: emlx(message)) ?? ""
        #expect(VerificationCodeManager.extractCode(from: text) == "445566")
    }

    @Test func malformedFilesDoNotCrash() {
        #expect(MIME.text(ofEMLX: Data()) == nil)
        #expect(MIME.text(ofEMLX: Data("pas un nombre\nSubject: x".utf8)) == nil)
        // Taille annoncée plus grande que le fichier.
        _ = MIME.text(ofEMLX: Data("999999\nContent-Type: text/plain\n\nabc".utf8))
        // Quoted-printable coupé au milieu d'une séquence.
        _ = MIME.text(ofEMLX: emlx("Content-Transfer-Encoding: quoted-printable\n\nabc=C"))
        _ = MIME.text(ofEMLX: emlx("Content-Transfer-Encoding: quoted-printable\n\n="))
        // Base64 invalide, multipart sans parties.
        _ = MIME.text(ofEMLX: emlx("Content-Transfer-Encoding: base64\n\n@@@"))
        _ = MIME.text(ofEMLX: emlx("Content-Type: multipart/mixed; boundary=x\n\n"))
    }
}
