import SwiftUI

/// The thinking orbs (ThinkingOrbsKit, vendored from Jot; MIT, see ThinkingOrbsKit/SOURCE.txt) in record red, for
/// every wait instead of a spinner: searching (the dotted globe) while a link is fetched, shaping while frames are cut.
struct OrbView: View {
    enum Kind { case searching, shaping }
    var kind: Kind
    var size: CGFloat

    var body: some View {
        // Drawn white on dark, then multiplied into Cut's red. The 20 px preset has fewer, bolder dots for small sizes.
        ThinkingOrb(state: kind == .searching ? .searching : .shaping,
                    size: size < 44 ? .px20 : .px64, theme: .dark, displaySize: size)
            .colorMultiply(.cRed)
            .accessibilityLabel(kind == .searching ? "Fetching" : "Cutting")
    }
}
