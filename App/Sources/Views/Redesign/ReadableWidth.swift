import SwiftUI

/// A dizájn 402 pt széles iPhone-ra készült. iPaden a tartalmat nem
/// széthúzzuk, hanem középre zárjuk egy olvasható sávban — egy 44 pt-es
/// összeg és egy 1024 pt széles sor együtt olvashatatlan.
struct ReadableWidth: ViewModifier {
    var maxWidth: CGFloat = 520

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func readableWidth(_ maxWidth: CGFloat = 520) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth))
    }
}
