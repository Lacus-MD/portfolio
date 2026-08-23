import SwiftUI

/// Egy adott naphoz tartozó kiolvasás a görbén.
struct ScrubReading: Equatable {
    struct Row: Equatable, Identifiable {
        var id: String
        var label: String
        var colorHex: UInt32
        var text: String
        var color: Color { Color(hex: colorHex) }
    }
    var date: Date?
    var rows: [Row]
}

/// Vékony sáv a görbén: megmutatja, mi volt az adott nap.
///
/// **A kiírt szám a NYERS érték, nem a rajzolté.** A görbét mozgóátlag simítja
/// az olvashatóságért; ha a sáv a simított értéket mutatná, a felület olyan
/// összeget írna ki, ami soha nem volt. A rajz közelít, a szám pontos.
struct ScrubBand: View {
    let fraction: Double
    let reading: ScrubReading
    let width: CGFloat
    let height: CGFloat
    var tint: Color

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "yyyy. MMM d."
        return f
    }()

    var body: some View {
        let x = width * fraction
        ZStack(alignment: .topLeading) {
            // A sáv szándékosan vékony és halvány: a görbét jelöli, nem takarja.
            Rectangle()
                .fill(tint.opacity(0.55))
                .frame(width: 1.5, height: height)
                .position(x: x, y: height / 2)

            callout
                // A buborék nem lóghat ki a széleken: a széleknél odatapad.
                .position(x: min(max(x, 78), width - 78), y: 30)
        }
        .allowsHitTesting(false)
    }

    private var callout: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let date = reading.date {
                Text(Self.formatter.string(from: date))
                    .font(DS.font(10.5, .medium))
                    .foregroundStyle(DS.Color.inkSoft(0.55))
            }
            ForEach(reading.rows) { row in
                HStack(spacing: 5) {
                    if !row.label.isEmpty {
                        Circle().fill(row.color).frame(width: 5, height: 5)
                        Text(row.label)
                            .font(DS.font(10.5, .regular))
                            .foregroundStyle(DS.Color.inkSoft(0.55))
                    }
                    Text(row.text)
                        .font(DS.font(11.5, .semibold).monospacedDigit())
                        .foregroundStyle(DS.Color.ink)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .pastelCardBackground(in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(DS.Color.inkSoft(0.10)))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .fixedSize()
    }
}

extension View {
    /// Koppintásra kiteszi a dátumsávot, és OTT IS HAGYJA; amíg látszik,
    /// húzással mozgatható; BÁRHOVÁ koppintva eltűnik.
    ///
    /// Korábban csak ugyanoda koppintva tűnt el, máshová koppintva
    /// átugrott — így nem volt egyértelmű módja becsukni. Most a koppintás
    /// egyszerű kapcsoló: ha látszik, elrejti; ha nem, kiteszi oda, ahová
    /// nyomtál. Mozgatni húzással lehet, ami amúgy is pontosabb.
    ///
    /// **Miért nem nyomva tartás:** a görbe egy `ScrollView`-ban ül. A sima
    /// `DragGesture` húzását a görgetés viszi el, a `LongPressGesture`-rel
    /// sorbafűzött változat pedig a szimulátorban egyáltalán nem sült el —
    /// mértem, a sáv meg sem jelent. A koppintás viszont nem versenyez a
    /// görgetéssel, és van egy előnye is: nem kell nyomva tartani ahhoz,
    /// hogy elolvasd, mennyi volt az aznapi érték.
    func scrubbable(width: CGFloat, fraction: Binding<Double?>) -> some View {
        contentShape(.rect)
            .onTapGesture { location in
                guard width > 0 else { return }
                let value = min(max(location.x / width, 0), 1)
                if fraction.wrappedValue != nil {
                    fraction.wrappedValue = nil
                } else {
                    fraction.wrappedValue = value
                }
            }
            // A sáv HÚZHATÓ, de csak amíg látszik.
            //
            // A `simultaneousGesture` itt kevés volt: a `ScrollView` a
            // vízszintes mozgást is magának kérte, és a sáv nem mozdult.
            // A `highPriorityGesture` elveszi a görgetéstől — viszont csak
            // akkor kapcsoljuk be, ha a sáv látszik (`GestureMask.none`,
            // amikor nem). Így rejtett sávnál a görbén is lehet görgetni,
            // láthatónál pedig az ujj a sávot viszi.
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0 else { return }
                        fraction.wrappedValue = min(max(value.location.x / width, 0), 1)
                    },
                including: fraction.wrappedValue == nil ? .none : .all
            )
    }
}

enum ScrubMath {
    /// A vízszintes helyhez legközelebbi pont indexe.
    ///
    /// `xs`-szel a pontok NEM egyenletesen oszlanak el (a napok szerint állnak),
    /// ezért ott tényleg keresni kell, nem elég szorozni.
    static func nearestIndex(to fraction: Double, xs: [Double]?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let xs, xs.count == count else {
            return min(max(Int((fraction * Double(count - 1)).rounded()), 0), count - 1)
        }
        var best = 0
        var bestDistance = Double.infinity
        for (index, x) in xs.enumerated() {
            let distance = abs(x - fraction)
            if distance < bestDistance { bestDistance = distance; best = index }
        }
        return best
    }
}
