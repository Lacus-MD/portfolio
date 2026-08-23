import Foundation
import PDFKit

/// Kivonat szövegének kinyerése PDF-ből.
///
/// A lakossági bankok (OTP is) PDF-ben adják a kivonatot; a CSV/Excel export a
/// vállalati csatornákon van. Egy generált — nem szkennelt — PDF-ben viszont ott
/// a szövegréteg, amit a PDFKit ki tud adni. Onnantól ugyanaz a dolgunk, mint
/// egy CSV-nél: felismerni a formátumot és sorokra bontani.
///
/// **A fájl nem megy sehova.** A kinyerés az eszközön történik, ahogy a
/// CSV-beolvasás is — egy bankkivonat tartalmát nem küldjük hálózatra.
enum PDFStatement {

    /// Igaz, ha a bájtok PDF-et jelentenek. A kiterjesztésre nem hagyatkozunk:
    /// a megosztólapról átnevezett fájl is érkezhet.
    static func looksLikePDF(_ data: Data) -> Bool {
        data.prefix(4).elementsEqual(Array("%PDF".utf8))
    }

    enum ExtractError: LocalizedError {
        case unreadable, noTextLayer

        var errorDescription: String? {
            switch self {
            case .unreadable:
                "A PDF-et nem sikerült megnyitni."
            case .noTextLayer:
                // Szkennelt kivonatnál nincs mit kiolvasni. Ezt kimondjuk,
                // nem próbálunk félig üres eredményt beolvasni.
                "Ebben a PDF-ben nincs szövegréteg — valószínűleg beszkennelt vagy képként mentett kivonat. Kérj a banktól letöltött (nem nyomtatott) példányt."
            }
        }
    }

    /// A PDF teljes szövege, oldalanként sorrendben.
    static func text(from data: Data) throws -> String {
        guard let document = PDFDocument(data: data) else { throw ExtractError.unreadable }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let text = page.string {
                pages.append(text)
            }
        }
        let joined = pages.joined(separator: "\n")
        // Egy oldalnyi fejléc még nem kivonat: 200 karakter alatt biztosan
        // nincs miből dolgozni.
        guard joined.trimmingCharacters(in: .whitespacesAndNewlines).count >= 200 else {
            throw ExtractError.noTextLayer
        }
        return joined
    }
}
