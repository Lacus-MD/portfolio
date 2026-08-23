import SwiftUI

/// Záró gomb natív Liquid Glass anyaggal.
///
/// Két hibát javít az előző, csupasz ikonhoz képest:
/// 1. **A találati felület 44×44 pt** — az Apple minimuma. Korábban csak maga a
///    18 pontos glifa volt kattintható, ezért „nem mindig ment".
/// 2. Az anyag a rendszeré, tehát sötét és világos háttéren is helyesen ül,
///    és megkapja az interaktív visszajelzést.
struct GlassCloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Bezárás")
    }
}

/// Elsődleges művelet üveg anyaggal, a platform színére hangolva.
struct GlassActionButton: View {
    let title: String
    var tint: Color = DS.Color.plum
    var foreground: Color = DS.Color.onShell()
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.button)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .contentShape(.rect(cornerRadius: DS.R.primaryButton))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(tint).interactive(),
                     in: .rect(cornerRadius: DS.R.primaryButton))
    }
}
