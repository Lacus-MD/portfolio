import SwiftUI

/// Lehúzás-frissítés — saját rajzolással.
///
/// **Miért nem a rendszer `.refreshable`-je:** az nyitva tartja az oldalt és
/// a saját pörgettyűjét mutatja, amíg a munka tart. Itt a kívánt viselkedés
/// más: húzás közben egy MEGFORDULÓ NYÍL jelzi, hogy elengedéskor indul; az
/// oldal azonnal visszaugrik; és felül egy témaszínű csík fut, amíg a
/// frissítés dolgozik, majd eltűnik.
///
/// **Miért nem gesztus:** a korábbi kézi megoldás DragGesture-t tett a teljes
/// görgetett tartalomra, és az a görgetés felismerésével versenyzett (akadó,
/// visszapattanó kinetika). Ez a változat csak a görgetés GEOMETRIÁJÁT
/// olvassa (`onScrollGeometryChange`) — nem vesz el semmit a görgetéstől.
/// Nyugalmi állapotban a kiolvasott érték állandó nulla, tehát nem is fut
/// az akció; számítás csak tényleges lehúzás közben történik.
struct PullRefresh: ViewModifier {
    /// A csík és a nyíl színe — témánként más, a hívó adja.
    let tint: Color
    let onRefresh: () async -> Void

    /// Ennyi pont lehúzás indít. A rendszerével nagyjából azonos érzet.
    static let threshold: CGFloat = 76

    @State private var pull: CGFloat = 0
    @State private var refreshing = false
    /// Egy lehúzás egy indítás: elengedés (visszatérés nullára) előtt nem
    /// indulhat újra, hiába marad a küszöb fölött az ujj.
    @State private var cooldown = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { _, value in
                // Négy pontonként lépünk: a nyíl mozgásához bőven elég, és
                // negyedeli az állapotírások számát húzás közben.
                let quantized = (value / 4).rounded() * 4
                if quantized != pull { pull = quantized }
                if value <= 0.5, cooldown, !refreshing { cooldown = false }
                guard !refreshing, !cooldown, value >= Self.threshold else { return }
                refreshing = true
                cooldown = true
                Task {
                    await onRefresh()
                    withAnimation(.easeOut(duration: 0.3)) { refreshing = false }
                }
            }
            .overlay(alignment: .top) { arrow }
            .overlay(alignment: .top) { bar }
            .sensoryFeedback(.impact(weight: .medium), trigger: refreshing) { _, new in new }
    }

    /// A húzás közbeni nyíl. A küszöb előtt lefelé mutat; a küszöbnél
    /// MEGFORDUL — ez jelzi, hogy elengedheted. Indítás után átadja a
    /// helyét a csíknak.
    @ViewBuilder private var arrow: some View {
        if pull > 10, !refreshing {
            let past = pull >= Self.threshold
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(past ? tint : DS.Color.inkSoft(0.45))
                .rotationEffect(.degrees(past ? 180 : 0))
                .animation(.snappy(duration: 0.22), value: past)
                .frame(width: 32, height: 32)
                .background(DS.Color.card.opacity(0.92), in: .circle)
                .overlay(Circle().stroke(DS.Color.inkSoft(0.10)))
                // A tartalommal együtt ereszkedik, de lassabban — így látszik,
                // hogy a húzáshoz tartozik, mégsem takarja a fejlécet.
                .offset(y: min(pull * 0.45, 54))
                .opacity(min(Double(pull) / 40, 1))
                .transition(.opacity)
                .accessibilityLabel(past ? "Engedd el a frissítéshez" : "Húzd tovább a frissítéshez")
        }
    }

    /// A frissítés alatti témaszínű csík — határozatlan futófénnyel, mert a
    /// banki + árfolyam-lekérés hossza előre nem ismert.
    @ViewBuilder private var bar: some View {
        if refreshing {
            GeometryReader { geo in
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let phase = (t.truncatingRemainder(dividingBy: 1.1)) / 1.1
                    let width = geo.size.width * 0.36
                    Capsule()
                        .fill(tint)
                        .frame(width: width, height: 3)
                        .offset(x: -width + (geo.size.width + width) * phase)
                }
            }
            .frame(height: 3)
            .clipped()
            .transition(.opacity)
            .accessibilityLabel("Frissítés folyamatban")
        }
    }
}

extension View {
    func pullRefresh(tint: Color, onRefresh: @escaping () async -> Void) -> some View {
        modifier(PullRefresh(tint: tint, onRefresh: onRefresh))
    }
}
