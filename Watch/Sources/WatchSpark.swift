import SwiftUI

/// Apró szikragörbe az órára — Path, nem Charts: kevesebb energia, kisebb kód.
struct WatchSpark: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let low = values.min() ?? 0, high = values.max() ?? 1
            let span = high - low
            Path { path in
                guard values.count >= 2 else { return }
                for (index, value) in values.enumerated() {
                    let x = geo.size.width * Double(index) / Double(values.count - 1)
                    let ratio = span > 0 ? (value - low) / span : 0.5
                    let y = geo.size.height * (1 - ratio)
                    if index == 0 { path.move(to: .init(x: x, y: y)) }
                    else { path.addLine(to: .init(x: x, y: y)) }
                }
            }
            .stroke(tint, style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}
