import SwiftUI

/// Lélegző (pulzáló) helyőrző a betöltés idejére.
///
/// Miért nem pörgő kerék: a kerék csak annyit mond, hogy „várj". A helyőrző
/// megmutatja, MI fog odakerülni és mekkora helyet foglal, így a tartalom
/// megérkezésekor nem ugrik szét a lap. A lélegzés ritmusa lassú (1,6 s),
/// mert egy vagyonkijelzőnél a nyugtalan felület rossz érzetet ad.
///
/// A „csökkentett mozgás" beállítást tiszteletben tartjuk: ott nincs animáció,
/// csak egy állandó, halvány kitöltés.
struct Breathing: ViewModifier {
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inhaled = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 0.5 : (inhaled ? 0.72 : 0.3))
            .animation(reduceMotion ? nil
                       : .easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(delay),
                       value: inhaled)
            .onAppear { inhaled = true }
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

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(DS.Color.ink)
            .frame(width: width, height: height)
            .breathing(delay: delay)
    }
}

/// Egy lélegző sor: ikon + két szövegsáv + érték. A hírek és a komponensek
/// listája pont ilyen alakú, így a betöltés alatt is ugyanaz a ritmus látszik.
struct SkeletonRow: View {
    var index: Int = 0

    var body: some View {
        // A késleltetés soronként lépcsőzik: a lista hullámban lélegzik, nem
        // egyszerre villan — ez érezhetően nyugodtabb.
        let delay = Double(index) * 0.14
        return HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: DS.R.rowIcon, style: .continuous)
                .fill(DS.Color.ink)
                .frame(width: 42, height: 42)
                .breathing(delay: delay)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBar(width: 132, height: 11, delay: delay)
                SkeletonBar(width: 88, height: 9, delay: delay + 0.05)
            }
            Spacer(minLength: 8)
            SkeletonBar(width: 54, height: 12, delay: delay + 0.1)
        }
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }
}

/// Több sor egyben, a szekció helyét kitöltve.
struct SkeletonRows: View {
    var count: Int = 2

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { SkeletonRow(index: $0) }
        }
    }
}
