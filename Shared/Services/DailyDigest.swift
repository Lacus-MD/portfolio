import Foundation

/// Egy nagyot mozdult komponens és az, hogy ez a TE pénzeden mennyit jelent.
struct DigestEntry: Identifiable, Hashable {
    enum Kind { case winner, loser }

    var id: String { move.name }
    let kind: Kind
    let move: ConstituentMove
    /// Forintban, a te alapbeli részesedésedre vetítve.
    ///
    /// Ez a szám a lényeg. Egy „NVIDIA −6%" főcím ijesztő; hogy ez nálad
    /// −1 900 Ft, az viszont megmondja, kell-e vele foglalkozni. Egy 3 757
    /// papírból álló világindexben egyetlen név ritkán mozdít sokat — ezt nem
    /// elkendőzni kell, hanem kiírni.
    let impactHUF: Decimal
}

/// Napi összefoglaló: ki nyert és ki bukott nagyot, és ha van hír, miért.
///
/// **Esemény-vezérelt, nem folyamatos.** Ha aznap semmi nem mozdult a küszöb
/// fölött, a szekció nem jelenik meg — egy „ma nem történt semmi" doboz minden
/// nap csak zaj. A hírt a `ConstituentWatcher` szintén csak a kiugrókhoz kéri le.
enum DailyDigest {

    /// Ekkora napi mozgástól számít egy komponens „nagyot mozdultnak".
    /// 2,5% nagyjából a napi szórás kétszerese a top-10 nevekre — az alatt
    /// minden nap volna találat, és a szekció elveszítené a jelentését.
    static let moveThreshold: Double = 2.5

    /// Ekkora napi PORTFÓLIÓ-mozgás fölött szólunk külön is.
    static let portfolioThreshold: Double = 1.5

    /// A legnagyobbat nyert és a legnagyobbat bukott komponens — mindkettő
    /// csak akkor, ha átlépte a küszöböt.
    static func entries(from moves: [ConstituentMove],
                        fundValueHUF: Decimal,
                        threshold: Double = moveThreshold) -> [DigestEntry] {
        func entry(_ move: ConstituentMove?, _ kind: DigestEntry.Kind) -> DigestEntry? {
            guard let move, abs(move.changePct) >= threshold else { return nil }
            let impact = fundValueHUF * Decimal(move.contributionPct) / 100
            return DigestEntry(kind: kind, move: move, impactHUF: impact)
        }
        let up = moves.filter { $0.changePct > 0 }.max { $0.changePct < $1.changePct }
        let down = moves.filter { $0.changePct < 0 }.min { $0.changePct < $1.changePct }
        return [entry(up, .winner), entry(down, .loser)].compactMap { $0 }
    }

    /// Egy mondat a nap portfólió-szintű mozgásáról, ha az kiugró volt.
    /// `nil`, ha a nap átlagos — akkor nincs mit mondani.
    static func portfolioHeadline(dayChangePct: Double,
                                  dayChangeHUF: Decimal,
                                  threshold: Double = portfolioThreshold) -> String? {
        guard abs(dayChangePct) >= threshold else { return nil }
        let amount = Fmt.huf(abs(dayChangeHUF))
        // ELŐJEL NÉLKÜLI nagyság kell, mert az irányt a mondat mondja ki.
        // A `Fmt.percent` kiírja a plusz jelet, és az `abs()` után ebből
        // „+94,79%-ot esett" lett — a szám és a szó egymásnak mondott ellent.
        let magnitude = Fmt.percentPlain(abs(dayChangePct))
        return dayChangePct > 0
            ? "A portfóliód ma \(magnitude)-ot emelkedett — \(amount) plusz."
            : "A portfóliód ma \(magnitude)-ot esett — \(amount) mínusz."
    }
}
