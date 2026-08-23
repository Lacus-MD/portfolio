import SwiftUI

/// Két oszlop ARÁNYOSAN elosztva, a rendelkezésre álló szélességből.
///
/// Nem `HStack`: az a tartalom belső méretéből osztana, és egy grafikon meg egy
/// kártyalista természetes szélessége semmit nem mond arról, hogyan érdemes a
/// lapot felosztani. Itt az arány a lap tulajdonsága, nem a tartalomé.
struct ProportionalColumns: Layout {
    /// Az ELSŐ oszlop részesedése a hasznos szélességből.
    var ratio: CGFloat = 0.52
    var spacing: CGFloat = 24

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        guard subviews.count == 2 else {
            return CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
        }
        let total = proposal.width ?? 0
        let usable = max(0, total - spacing)
        let leadWidth = usable * ratio
        let heights = [
            subviews[0].sizeThatFits(.init(width: leadWidth, height: nil)).height,
            subviews[1].sizeThatFits(.init(width: usable - leadWidth, height: nil)).height,
        ]
        return CGSize(width: total, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let usable = max(0, bounds.width - spacing)
        let leadWidth = usable * ratio
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY),
                          anchor: .topLeading,
                          proposal: .init(width: leadWidth, height: nil))
        subviews[1].place(at: CGPoint(x: bounds.minX + leadWidth + spacing, y: bounds.minY),
                          anchor: .topLeading,
                          proposal: .init(width: usable - leadWidth, height: nil))
    }
}

/// iPaden (és fekvő Max iPhone-on) két arányos oszlop, iPhone-on egymás alatt.
///
/// A törésponthoz a méretosztályt használjuk, nem a nyers pontszélességet: a
/// megosztott képernyős iPad fele ugyanolyan szűk, mint egy telefon, és ott a
/// két oszlop olvashatatlan volna.
struct AdaptiveColumns<Lead: View, Trail: View>: View {
    var ratio: CGFloat = 0.52
    var spacing: CGFloat = 24
    @ViewBuilder var lead: Lead
    @ViewBuilder var trail: Trail

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            ProportionalColumns(ratio: ratio, spacing: spacing) {
                VStack(alignment: .leading, spacing: 20) { lead }
                VStack(alignment: .leading, spacing: 20) { trail }
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                lead
                trail
            }
        }
    }
}

/// Igaz, ha van hely két oszlopnak. A nézetek ebből tudják, mekkora olvasható
/// sávot kérjenek — egyoszlopos lapnál 520 pt, kétoszloposnál a duplája.
extension EnvironmentValues {
    var isWideLayout: Bool { horizontalSizeClass == .regular }
}
