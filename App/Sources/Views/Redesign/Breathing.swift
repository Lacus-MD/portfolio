import SwiftUI

/// Nyugodt helyőrző a betöltés idejére.
///
/// Miért nem pörgő kerék: a kerék csak annyit mond, hogy „várj". A helyőrző
/// megmutatja, MI fog odakerülni és mekkora helyet foglal, így a tartalom
/// megérkezésekor nem ugrik szét a lap. A lélegzés ritmusa lassú (1,6 s),
/// mert egy vagyonkijelzőnél a nyugtalan felület rossz érzetet ad.
///
/// Korábban minden egyes sáv külön, végtelen SwiftUI-animációt futtatott. Egy
/// híroldal betöltésekor ez egyszerre több tucat animációs tranzakciót és
/// aktív réteget jelentett. Most egy teljes skeleton-listát EGY 15 fps-es
/// idővonal hajt: marad a finom életjel, de nem versenyez a görgetéssel.
private func skeletonOpacity(at date: Date, delay: Double) -> Double {
    let seconds = date.timeIntervalSinceReferenceDate - delay
    let wave = (sin(seconds * .pi * 1.25) + 1) / 2
    return 0.30 + wave * 0.22
}

struct Breathing: ViewModifier {
    var delay: Double = 0

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
            content.opacity(skeletonOpacity(at: timeline.date, delay: delay))
        }
    }
}

extension View {
    func breathing(delay: Double = 0) -> some View { modifier(Breathing(delay: delay)) }
}

/// Egy lélegző sáv — szöveg helyén.
struct SkeletonBar: View {
    var width: CGFloat?
    var height: CGFloat = 11
    var delay: Double = 0
    /// A szülő közös idővonala. Ha nincs, a magányos sáv saját, olcsó
    /// idővonalat kap; listában mindig megadjuk.
    var timelineDate: Date? = nil

    @ViewBuilder
    var body: some View {
        if let timelineDate {
            bar.opacity(skeletonOpacity(at: timelineDate, delay: delay))
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                bar.opacity(skeletonOpacity(at: timeline.date, delay: delay))
            }
        }
    }

    private var bar: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(DS.Color.ink)
            .frame(width: width, height: height)
    }
}

/// Egy lélegző sor: ikon + két szövegsáv + érték. A hírek és a komponensek
/// listája pont ilyen alakú, így a betöltés alatt is ugyanaz a ritmus látszik.
struct SkeletonRow: View {
    var index: Int = 0
    var timelineDate: Date? = nil

    var body: some View {
        // A késleltetés soronként lépcsőzik: a lista hullámban lélegzik, nem
        // egyszerre villan — ez érezhetően nyugodtabb.
        let delay = Double(index) * 0.14
        return HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: DS.R.rowIcon, style: .continuous)
                .fill(DS.Color.ink)
                .frame(width: 42, height: 42)
                .opacity(timelineDate.map { skeletonOpacity(at: $0, delay: delay) } ?? 0.42)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBar(width: 132, height: 11, delay: delay,
                            timelineDate: timelineDate)
                SkeletonBar(width: 88, height: 9, delay: delay + 0.05,
                            timelineDate: timelineDate)
            }
            Spacer(minLength: 8)
            SkeletonBar(width: 54, height: 12, delay: delay + 0.1,
                        timelineDate: timelineDate)
        }
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }
}

/// Több sor egyben, a szekció helyét kitöltve.
struct SkeletonRows: View {
    var count: Int = 2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) {
                    SkeletonRow(index: $0, timelineDate: timeline.date)
                }
            }
        }
    }
}
