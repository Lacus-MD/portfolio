import SwiftUI

/// Az app jele: ugyanaz az emelkedő görbe, mint az ikonon.
///
/// A handoffban itt egy monogramos profilkép állt („B"). Egy EGYFELHASZNÁLÓS
/// appban ez semmit nem jelent — nincs kitől megkülönböztetni téged. Helyette
/// az app saját jelét visszük, ami legalább identitás, nem álca.
struct AppMark: View {
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().fill(DS.Color.plum)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                Path { p in
                    p.move(to: .init(x: w * 0.20, y: h * 0.66))
                    p.addCurve(to: .init(x: w * 0.50, y: h * 0.56),
                               control1: .init(x: w * 0.30, y: h * 0.64),
                               control2: .init(x: w * 0.38, y: h * 0.50))
                    p.addCurve(to: .init(x: w * 0.80, y: h * 0.34),
                               control1: .init(x: w * 0.62, y: h * 0.62),
                               control2: .init(x: w * 0.68, y: h * 0.36))
                }
                .stroke(DS.Color.coral,
                        style: .init(lineWidth: w * 0.10, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
