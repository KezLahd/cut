import SwiftUI

/// Cut's mark and wordmark, drawn from the same geometry as design/cut-look.html ("Sliced", True brackets):
/// stroke 13, corner radius 4, round ends; x-height runs 6…44 in letter units. One diagonal cut runs through
/// the whole drawing and the part above it is nudged right.
enum Brand {
    static let red = Color(red: 1, green: 0.231, blue: 0.184)  // #FF3B2F, record red

    static let stroke: CGFloat = 13

    /// c, u, t, spaced by the board's rule (c→u gap just under a stroke, u→crossbar a little tighter).
    static func word() -> (c: Path, ut: Path) {
        var c = Path()
        c.move(to: CGPoint(x: 24, y: 6)); c.addLine(to: CGPoint(x: 4, y: 6))
        c.addQuadCurve(to: CGPoint(x: 0, y: 10), control: CGPoint(x: 0, y: 6))
        c.addLine(to: CGPoint(x: 0, y: 40))
        c.addQuadCurve(to: CGPoint(x: 4, y: 44), control: CGPoint(x: 0, y: 44))
        c.addLine(to: CGPoint(x: 24, y: 44))

        var ut = Path()
        ut.move(to: CGPoint(x: 48, y: 6)); ut.addLine(to: CGPoint(x: 48, y: 40))
        ut.addQuadCurve(to: CGPoint(x: 52, y: 44), control: CGPoint(x: 48, y: 44))
        ut.addLine(to: CGPoint(x: 78, y: 44))
        ut.move(to: CGPoint(x: 78, y: 6)); ut.addLine(to: CGPoint(x: 78, y: 44))
        ut.move(to: CGPoint(x: 110, y: -12)); ut.addLine(to: CGPoint(x: 110, y: 40))
        ut.addQuadCurve(to: CGPoint(x: 114, y: 44), control: CGPoint(x: 110, y: 44))
        ut.addLine(to: CGPoint(x: 123, y: 44))
        ut.move(to: CGPoint(x: 100, y: 6)); ut.addLine(to: CGPoint(x: 124, y: 6))
        return (c, ut)
    }

    /// The icon: the wordmark's c facing a mirrored c, [ ].
    static func mark() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 24, y: 6)); p.addLine(to: CGPoint(x: 4, y: 6))
        p.addQuadCurve(to: CGPoint(x: 0, y: 10), control: CGPoint(x: 0, y: 6))
        p.addLine(to: CGPoint(x: 0, y: 40))
        p.addQuadCurve(to: CGPoint(x: 4, y: 44), control: CGPoint(x: 0, y: 44))
        p.addLine(to: CGPoint(x: 24, y: 44))
        p.move(to: CGPoint(x: 50, y: 6)); p.addLine(to: CGPoint(x: 70, y: 6))
        p.addQuadCurve(to: CGPoint(x: 74, y: 10), control: CGPoint(x: 74, y: 6))
        p.addLine(to: CGPoint(x: 74, y: 40))
        p.addQuadCurve(to: CGPoint(x: 70, y: 44), control: CGPoint(x: 74, y: 44))
        p.addLine(to: CGPoint(x: 50, y: 44))
        return p
    }
}

/// Draws strokes in letter units into a frame, sliced along a line from (x0, yL) to (x1, yR).
private struct SlicedCanvas: View {
    var bounds: CGRect            // letter-unit box to fit
    var slice: (x0: CGFloat, yL: CGFloat, x1: CGFloat, yR: CGFloat, dx: CGFloat)
    var layers: [(Path, Color)]

    var body: some View {
        Canvas { ctx, size in
            let k = min(size.width / bounds.width, size.height / bounds.height)
            let ox = (size.width - bounds.width * k) / 2 - bounds.minX * k
            let oy = (size.height - bounds.height * k) / 2 - bounds.minY * k
            let gap: CGFloat = 1.6
            let s = slice
            var top = Path()
            top.move(to: CGPoint(x: s.x0 - 30, y: -100)); top.addLine(to: CGPoint(x: s.x1 + 30, y: -100))
            top.addLine(to: CGPoint(x: s.x1 + 30, y: s.yR - gap)); top.addLine(to: CGPoint(x: s.x0 - 30, y: s.yL - gap)); top.closeSubpath()
            var bottom = Path()
            bottom.move(to: CGPoint(x: s.x0 - 30, y: s.yL + gap)); bottom.addLine(to: CGPoint(x: s.x1 + 30, y: s.yR + gap))
            bottom.addLine(to: CGPoint(x: s.x1 + 30, y: 200)); bottom.addLine(to: CGPoint(x: s.x0 - 30, y: 200)); bottom.closeSubpath()
            let style = StrokeStyle(lineWidth: Brand.stroke, lineCap: .round, lineJoin: .round)
            for (clip, dx) in [(top, s.dx), (bottom, CGFloat(0))] {
                var c = ctx
                c.translateBy(x: ox, y: oy)
                c.scaleBy(x: k, y: k)
                c.clip(to: clip)
                c.translateBy(x: dx, y: 0)
                for (path, color) in layers { c.stroke(path, with: .color(color), style: style) }
            }
        }
    }
}

/// The sliced "cut" wordmark. Set its height; the width follows (about 1.9 × height).
struct Wordmark: View {
    var c: Color = Brand.red
    var ut: Color = .primary

    var body: some View {
        let w = Brand.word()
        SlicedCanvas(bounds: CGRect(x: -7, y: -19, width: 141, height: 70),
                     slice: (x0: -10, yL: 36, x1: 130.5, yR: 14, dx: 3.5),
                     layers: [(w.c, c), (w.ut, ut)])
            .aspectRatio(141 / 70, contentMode: .fit)
    }
}

/// The sliced [ ] mark.
struct Mark: View {
    var color: Color = Brand.red

    var body: some View {
        SlicedCanvas(bounds: CGRect(x: -7, y: -1, width: 92, height: 52),
                     slice: (x0: -10, yL: 37, x1: 90, yR: 13, dx: 4),
                     layers: [(Brand.mark(), color)])
            .aspectRatio(92 / 52, contentMode: .fit)
    }
}
