import SwiftUI

/// Gördülő számjegyek — a handoff „odometer" eleme.
///
/// Minden számjegy egy négycellás függőleges szalag `(d+7)%10 … d`, ami
/// −75%-ot csúszik, így a célszámjegyen áll meg. A cellák **fix szélesek**
/// és középre igazítottak: a Poppins számjegyei nem táblázatos szélességűek,
/// és egy keskeny „1" különben hézagnak látszana.
///
/// Csak pénzösszegre használjuk, százalékra nem — ahogy a handoff előírja.
struct Odometer: View {
    let text: String
    var font: Font = DS.display
    var cellHeight: CGFloat = 48
    var digitWidth: CGFloat = 0.6      // em-ben
    var delay: Double = 0.20
    var perDigit: Double = 0.07

    @State private var rolled = false

    private var fontSize: CGFloat { cellHeight / 48 * 44 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                if let digit = character.wholeNumberValue {
                    cell(digit: digit, order: digitOrder(upTo: index))
                } else {
                    Text(String(character))
                        .font(font)
                        // Csoportelválasztó és pénznem: keskenyebb köz.
                        .padding(.horizontal, character == " " ? fontSize * 0.11 : 0)
                }
            }
        }
        .onAppear {
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.15)) { rolled = true }
        }
    }

    /// Hányadik SZÁMJEGY ez balról — a késleltetés ez alapján lépcsőzik.
    private func digitOrder(upTo index: Int) -> Int {
        text.prefix(index).filter(\.isNumber).count
    }

    private func cell(digit: Int, order: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { step in
                Text("\((digit + 7 + step) % 10)")
                    .font(font)
                    .frame(height: cellHeight)
            }
        }
        .frame(width: fontSize * digitWidth, height: cellHeight, alignment: .top)
        .offset(y: rolled ? -cellHeight * 3 : 0)
        .clipped()
        .animation(
            .timingCurve(0.16, 1, 0.3, 1, duration: 1.15)
                .delay(delay + Double(order) * perDigit),
            value: rolled
        )
    }
}
