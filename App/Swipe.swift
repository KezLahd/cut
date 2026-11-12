import SwiftUI
import UIKit

// Swipe to delete, the same as Jot's list.

/// Swipe a row left to show Delete, the way iOS's own lists do: a system-red pill with a trash icon,
/// inset from the edge. There's no full-swipe delete; past the button the row only stretches a little.
/// One row open at a time; tapping an open row or scrolling closes it, and a swipe never opens the row.
struct SwipeToDelete: ViewModifier {
    let id: String
    @Binding var open: String?
    var enabled: Bool
    var title: String
    var action: () -> Void
    @State private var drag: CGFloat = 0
    @State private var horizontal: Bool?
    @State private var gone = false
    @State private var width: CGFloat = 0
    private let button: CGFloat = 72
    private let gap: CGFloat = 12
    private var reveal: CGFloat { button + gap * 2 }

    private var resting: CGFloat { open == id ? -reveal : 0 }
    /// Follows the finger up to the button, then resists.
    private var x: CGFloat {
        if gone { return -width - 20 }
        let raw = min(0, resting + drag)
        return raw < -reveal ? -reveal - (-raw - reveal) * 0.25 : raw
    }
    private var swiping: Bool { horizontal == true || open == id }

    func body(content: Content) -> some View {
        if !enabled {
            content
        } else {
            content
                // Mid-swipe or open, the row underneath takes no taps, so it never opens by accident.
                .allowsHitTesting(!swiping)
                .overlay { if open == id { Color.clear.contentShape(Rectangle()).onTapGesture { close() } } }
                .offset(x: x)
                .background(alignment: .trailing) {
                    if x < 0 {
                        Button(action: remove) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: max(0, min(-x, reveal + 40) - gap * 2))
                                .frame(maxHeight: .infinity)
                                .background(Color.red, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .padding(.vertical, 10)
                                .padding(.horizontal, gap)
                                .opacity(min(1, -x / (reveal * 0.6)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(title)
                    }
                }
                .contentShape(Rectangle())
                .clipped()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                // A UIKit pan that only starts when the finger is moving sideways, the way iOS's own lists
                // decide. Anything more vertical is left to the scroll view, so scrolling and pull-to-refresh
                // never get swallowed by a swipe.
                .gesture(SidewaysPan { dx in
                    if horizontal != true {
                        horizontal = true
                        if open != nil, open != id { withAnimation(.snappy(duration: 0.25)) { open = nil } }
                    }
                    drag = dx
                } ended: { dx, velocity in
                    let landed = resting + dx + velocity * 0.08
                    withAnimation(.snappy(duration: 0.3)) {
                        open = landed < -reveal / 2 ? id : nil
                        drag = 0
                    }
                    // Let the touch finish before the row takes taps again.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { horizontal = nil }
                })
                .accessibilityAction(named: title, remove)
        }
    }

    private func close() { withAnimation(.snappy(duration: 0.25)) { open = nil; drag = 0 } }

    private func remove() {
        withAnimation(.snappy(duration: 0.25)) { gone = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            open = nil
            drag = 0
            action()
            gone = false
        }
    }
}

/// A pan that begins only for a mostly sideways movement and never runs alongside the scroll view.
private struct SidewaysPan: UIGestureRecognizerRepresentable {
    var changed: (CGFloat) -> Void
    var ended: (_ dx: CGFloat, _ velocity: CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let dx = pan.translation(in: pan.view).x
        switch pan.state {
        case .changed: changed(dx)
        case .ended, .cancelled, .failed: ended(dx, pan.velocity(in: pan.view).x)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y) * 1.5
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }
    }
}
