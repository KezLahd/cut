import SwiftUI
import UIKit

extension Color {
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }

    /// Dark is a warm charcoal, a darkroom under the red safelight, not pure black: on black the screen's edge
    /// disappeared into the bezel. Surfaces step up from it; record red stays above 5:1 against it.
    static let cBg = dynamic(0xF7F6F4, 0x131111)
    static let cSurface = dynamic(0xFFFFFF, 0x1E1B1B)
    static let cSurface2 = dynamic(0xE9E8E5, 0x2A2626)
    static let cInk = dynamic(0x111111, 0xF3F3F3)
    static let cMute = dynamic(0x6E6E6E, 0x8B8B8B)
    static let cRed = Brand.red
}

extension Font {
    /// Schibsted Grotesk, for everything but times.
    static func app(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Schibsted Grotesk", size: size).weight(weight)
    }

    /// Times and counts, in the same face as everything else.
    /// (Was JetBrains Mono; Kez didn't like the monospace.)
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Schibsted Grotesk", size: size + 1).weight(weight)
    }
}

/// Side margins: text always sits a little further in than containers and buttons (Kez's rule, shared with Jot), so
/// words line up with the text inside the search field and buttons rather than with their edges.
enum Inset {
    static let container: CGFloat = 16
    static let text: CGFloat = 26
}

/// "0:14", "1:02:03".
func timecode(_ seconds: Double) -> String {
    let s = Int(seconds.rounded(.down))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

/// The one thing to act on: solid record red. Corners are squared off like the bracket mark, not round.
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 46
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.app(16, .semibold))
            .foregroundStyle(enabled ? .white : Color.cMute)
            .padding(.horizontal, 16)
            .frame(minHeight: height)
            .background(enabled ? Color.cRed : Color.cSurface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.snappy(duration: 0.2), value: enabled)
    }
}

/// Beside it: ink on grey.
struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 46
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.app(16, .semibold))
            .foregroundStyle(Color.cInk)
            .padding(.horizontal, 15)
            .frame(minHeight: height)
            .background(Color.cSurface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: Inline layout
// Cut lays everything out inline, like an edit list: rows on hairlines under short labels, no cards or boxes.

/// A thin rule across the page.
struct Hairline: View {
    var body: some View { Rectangle().fill(Color.cInk.opacity(0.13)).frame(height: 0.5) }
}

/// A section's name in red mono caps, with a rule running off to the right and an optional count.
struct SectionLabel: View {
    var title: String
    var trailing: String? = nil
    init(_ title: String, trailing: String? = nil) { self.title = title; self.trailing = trailing }

    var body: some View {
        HStack(spacing: 10) {
            Text(title.uppercased()).font(.mono(11, .medium)).tracking(0.8).foregroundStyle(Color.cRed)
            Rectangle().fill(Color.cInk.opacity(0.13)).frame(height: 0.5)
            if let trailing { Text(trailing).font(.mono(11)).foregroundStyle(Color.cMute) }
        }
        .padding(.top, 28).padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A row on a hairline: a glyph, a name and a note, and whatever it ends on.
struct LineRow<Trailing: View>: View {
    var icon: String?
    var title: String
    var note: String?
    var tint: Color = .cRed
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon).font(.system(size: 16, weight: .medium)).foregroundStyle(tint).frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(16, .medium)).foregroundStyle(Color.cInk)
                if let note { Text(note).font(.app(13)).foregroundStyle(Color.cMute) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 13)
        .contentShape(.rect)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

extension LineRow where Trailing == RowChevron {
    init(icon: String?, title: String, note: String? = nil, tint: Color = .cRed) {
        self.init(icon: icon, title: title, note: note, tint: tint) { RowChevron() }
    }
}

struct RowChevron: View {
    var body: some View { Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.cMute) }
}

/// A tappable row: a faint red wash under the finger, edge to edge.
struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(Color.cRed.opacity(configuration.isPressed ? 0.08 : 0).padding(.horizontal, -18))
    }
}

/// Options as plain words in a line: the chosen one in ink with a red bar under it.
struct InlineChoice<Value: Hashable>: View {
    var label: String?
    var options: [(Value, String)]
    @Binding var selection: Value
    var spacing: CGFloat = 16

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if let label {
                Text(label).font(.app(15, .medium)).foregroundStyle(Color.cInk).frame(width: 110, alignment: .leading)
            }
            HStack(spacing: spacing) {
                ForEach(options, id: \.0) { value, name in
                    let on = value == selection
                    Button { withAnimation(.snappy(duration: 0.2)) { selection = value } } label: {
                        Text(name).font(.app(15, on ? .semibold : .medium))
                            .foregroundStyle(on ? Color.cInk : Color.cMute)
                            .padding(.vertical, 6)
                            .overlay(alignment: .bottom) { if on { Rectangle().fill(Color.cRed).frame(height: 2) } }
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

/// A setting picked by sliding: the name on the left, the value large in red on the right, and a slider that
/// snaps to each stop with a tick of haptics.
struct StopSlider: View {
    var label: String
    var stops: [Double]
    var name: (Double) -> String
    @Binding var value: Double

    private var index: Binding<Double> {
        Binding(get: { Double(stops.firstIndex(of: value) ?? stops.indices.lowerBound) },
                set: { value = stops[min(stops.count - 1, max(0, Int($0.rounded())))] })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline) {
                Text(label).font(.app(15, .medium)).foregroundStyle(Color.cInk)
                Spacer()
                Text(name(value)).font(.mono(22, .semibold)).foregroundStyle(Color.cRed)
                    .contentTransition(.numericText()).animation(.snappy(duration: 0.2), value: value)
            }
            // No labels beside the track, so every slider runs the full width; the ends are named underneath.
            Slider(value: index, in: 0...Double(stops.count - 1), step: 1) { Text(label) }
            .tint(Color.cRed)
            .accessibilityValue(name(value))
            .sensoryFeedback(.selection, trigger: value)
            HStack {
                Text(name(stops[0]))
                Spacer()
                Text(name(stops[stops.count - 1]))
            }
            .font(.mono(10.5)).foregroundStyle(Color.cMute)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Hairline() }
    }
}
