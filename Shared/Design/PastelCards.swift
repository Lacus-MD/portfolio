import SwiftUI

struct CardPanelPalette {
    let baseColors: [Color]
    let cornerColors: [Color]
    let shadow: Color

    /// Visszafelé kompatibilis név, de már nem fix pasztell: minden panel az
    /// aktív téma vásznából, kártyájából és első két akcentusából épül fel.
    static var softPastel: Self {
        Self(
            baseColors: [DS.Color.card, DS.Color.canvas],
            cornerColors: [DS.Color.accent(0), DS.Color.accent(1)],
            shadow: DS.Color.accent(0).opacity(0.14)
        )
    }
}

struct PastelPanelBackground<S: Shape>: View {
    let shape: S
    let palette: CardPanelPalette
    let opacity: Double

    init(shape: S, palette: CardPanelPalette = .softPastel, opacity: Double = 1) {
        self.shape = shape
        self.palette = palette
        self.opacity = opacity
    }

    var body: some View {
        shape
            // Az árnyék csak egy egyszerű alakzaton készül. Korábban a két
            // gradientet előbb össze kellett kompozitálni és clipelni, majd
            // erről a teljes offscreen képről számolódott az árnyék minden
            // kártyánál. Görgetés közben ez volt a legdrágább közös réteg.
            .fill(palette.baseColors.first ?? .clear)
            .shadow(color: palette.shadow.opacity(opacity), radius: 10, x: 0, y: 5)
            .overlay {
                shape.fill(
                LinearGradient(
                    colors: palette.baseColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                )
            }
            .overlay {
                shape.fill(
                    RadialGradient(
                        colors: [
                            palette.cornerColors[0].opacity(min(0.22, 0.45 * opacity)),
                            palette.cornerColors[1].opacity(min(0.12, 0.24 * opacity)),
                            .clear
                        ],
                        center: UnitPoint(x: 0.98, y: 0.04),
                        startRadius: 0,
                        endRadius: 170
                    )
                )
            }
            .opacity(opacity)
    }
}

extension View {
    func pastelCardBackground<S: Shape>(
        in shape: S,
        palette: CardPanelPalette = .softPastel,
        opacity: Double = 1
    ) -> some View {
        background(PastelPanelBackground(shape: shape, palette: palette, opacity: opacity))
    }
}
