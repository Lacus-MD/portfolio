import SwiftUI

struct CardPanelPalette {
    let baseColors: [Color]
    let cornerColors: [Color]
    let shadow: Color

    static let softPastel = Self(
        baseColors: [Color(hex: 0xF6F9FF), Color(hex: 0xEDF3FF)],
        cornerColors: [Color(hex: 0x798CFF), Color(hex: 0x5D7BFF)],
        shadow: Color(hex: 0x566AE8).opacity(0.16)
    )
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
