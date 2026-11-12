import SwiftUI

/// Pull to refresh, Cut style. Pulling grows one tall bracket in the middle that splits into [ and ] and keeps
/// spreading the further you pull, going red once a let-go will refresh. Let go and they draw back in while a
/// strip of clips rolls between them for as long as the refresh takes. When it's done the strip eases to a
/// stop, one diagonal cut goes through it (the top half slips right, as in the logo), and the brackets slam
/// shut into the sliced mark before tucking away.
struct PullBrackets: View {
    var pull: CGFloat
    var refreshStart: Date?
    /// Seconds after `refreshStart` when the refresh finished; nil while it's still going.
    var doneAfter: TimeInterval?
    /// How far apart the brackets were when let go, so they draw in from there.
    var released: CGFloat = PullBrackets.rest
    /// Stay as the sliced mark once shut, instead of tucking away (the share sheet ends on it).
    var keep = false

    static let threshold: CGFloat = 86
    /// The film always rolls at least this long, so a quick refresh still reads.
    static let minimumLoad: TimeInterval = 1.4
    /// After `doneAfter`: when the cut goes through, when the brackets meet, and when it's all gone.
    static let sliceAfter: TimeInterval = 0.38
    static let snapAfter: TimeInterval = 0.84
    static let endAfter: TimeInterval = 1.35

    /// Letter units to points; the stroke stays the logo's 13 units.
    private static let k: CGFloat = 24.0 / 51
    /// Half a bracket's width with its stroke, in points.
    private static let half: CGFloat = 37 * k / 2
    /// Where each bracket's centre sits when the pair is shut into the mark.
    private static let shut: CGFloat = 25 * k
    /// Where they rest while the film rolls.
    static let rest: CGFloat = 44
    /// The arms reach this far up and down from the middle, in letter units: taller than the logo's c.
    private static let arm: CGFloat = 30
    private static let filmSpeed: CGFloat = 32
    /// Seconds after letting go for the pull to spring back up and the brackets to settle.
    static let settle: TimeInterval = 0.42

    /// How far apart the brackets sit for a given pull: they split, go red at the line, and keep spreading.
    static func spread(for pull: CGFloat) -> CGFloat {
        let q = min(1, pull / threshold)
        let split = ease((q - 0.3) / 0.7)
        let extra = pull > threshold ? 46 * (1 - exp(-(pull - threshold) / 70)) : 0
        return shut + (50 - shut) * split + extra
    }

    /// How hard the pull is stretching past the line, 0 to nearly 1: the brackets grow taller and thinner with it.
    static func stretch(for pull: CGFloat) -> CGFloat {
        pull > threshold ? 1 - exp(-(pull - threshold) / 110) : 0
    }

    /// A tick for each step of overpull. The steps close up the further you go, so the haptics speed up like
    /// a rubber band getting tighter (the scroll view's own resistance would otherwise slow them down).
    static func stretchStep(for pull: CGFloat) -> Int {
        guard pull > threshold + 20 else { return 0 }
        return min(120, 1 + Int(pow((pull - threshold - 20) / 30, 1.7)))
    }

    /// Ticks firm up as the band tightens.
    static func stretchIntensity(_ step: Int) -> Double { 0.3 + 0.7 * min(1, Double(step) / 22) }

    var body: some View {
        TimelineView(.animation(paused: refreshStart == nil)) { context in
            let t = refreshStart.map { context.date.timeIntervalSince($0) }
            let pose = t.map(release) ?? pulling
            Canvas { ctx, size in draw(pose, in: &ctx, size: size) }
                .scaleEffect(pose.scale)
                .opacity(pose.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct Pose {
        var spread: CGFloat = PullBrackets.rest
        var leftOpacity: CGFloat = 1
        var rightOpacity: CGFloat = 1
        var scale: CGFloat = 1
        var colour: Color = .cRed
        var film: CGFloat = 0
        var filmX: CGFloat = 0
        var slice: CGFloat = 0
        var opacity: CGFloat = 1
        var stretch: CGFloat = 0
    }

    private var pulling: Pose {
        let q = min(1, pull / Self.threshold)
        let appear = min(1, q / 0.3)
        var pose = Pose()
        pose.spread = Self.spread(for: pull)
        pose.leftOpacity = appear
        pose.rightOpacity = Self.ease((q - 0.3) / 0.7)
        pose.scale = 0.6 + 0.4 * appear
        pose.colour = q >= 1 ? .cRed : .cMute
        pose.stretch = Self.stretch(for: pull)
        return pose
    }

    private func release(_ t: TimeInterval) -> Pose {
        var pose = Pose()
        let s = doneAfter.map { t - $0 } ?? -1
        let resting = released + (Self.rest - released) * Self.ease(t / 0.36)
        // The film starts the moment you let go and rolls while the brackets draw in.
        pose.film = Self.ease(t / 0.18) * (1 - Self.ease((s - 0.62) / 0.16))
        pose.filmX = filmX(t)
        pose.slice = Self.ease((s - Self.sliceAfter) / 0.12)
        let shut = Self.slam((s - 0.62) / 0.22)
        pose.spread = resting + (Self.shut - resting) * shut
        let u = (s - Self.snapAfter) / 0.24
        let bounce: CGFloat = u > 0 && u < 1 ? 0.2 * CGFloat(sin(.pi * u) * (1 - u)) : 0
        let away = keep ? 0 : Self.ease((s - 1.05) / 0.26)
        pose.scale = (1 + bounce) * (1 - 0.5 * away)
        pose.opacity = 1 - away
        return pose
    }

    /// How far the strip has rolled; once loaded it eases to a stop over a third of a second.
    private func filmX(_ t: TimeInterval) -> CGFloat {
        let v = Self.filmSpeed
        let t = max(0, t)
        guard let done = doneAfter, t > done else { return v * CGFloat(t) }
        let u = CGFloat(min(t - done, 0.35))
        return v * CGFloat(done) + v * (u - u * u / (2 * 0.35))
    }

    // MARK: Drawing

    private func draw(_ pose: Pose, in ctx: inout GraphicsContext, size: CGSize) {
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        let w = size.width
        let lineY: (CGFloat) -> CGFloat = { x in mid.y + 3 - 0.24 * (x - mid.x) }
        let gap = 1.1 * pose.slice
        let dx = 3.2 * pose.slice

        var top = Path()
        top.move(to: CGPoint(x: -50, y: -400)); top.addLine(to: CGPoint(x: w + 50, y: -400))
        top.addLine(to: CGPoint(x: w + 50, y: lineY(w + 50) - gap)); top.addLine(to: CGPoint(x: -50, y: lineY(-50) - gap)); top.closeSubpath()
        var bottom = Path()
        bottom.move(to: CGPoint(x: -50, y: lineY(-50) + gap)); bottom.addLine(to: CGPoint(x: w + 50, y: lineY(w + 50) + gap))
        bottom.addLine(to: CGPoint(x: w + 50, y: size.height + 400)); bottom.addLine(to: CGPoint(x: -50, y: size.height + 400)); bottom.closeSubpath()

        for (clip, shift) in [(top, dx), (bottom, CGFloat(0))] {
            var c = ctx
            if pose.slice > 0 { c.clip(to: clip) }
            c.translateBy(x: shift, y: 0)
            film(pose, in: &c, mid: mid)
            brackets(pose, in: &c, mid: mid)
        }
    }

    /// A roll of clips running right to left between the brackets, sprocket holes along both edges.
    private func film(_ pose: Pose, in ctx: inout GraphicsContext, mid: CGPoint) {
        guard pose.film > 0 else { return }
        let inner = max(0, pose.spread - Self.half - 3)
        guard inner > 1 else { return }
        var c = ctx
        c.clip(to: Path(CGRect(x: mid.x - inner, y: mid.y - 16, width: inner * 2, height: 32)))
        let fh: CGFloat = 20, fw = fh * 9 / 16, period = fw + 3
        let first = Int(((pose.filmX - inner) / period).rounded(.down)) - 1
        for i in first..<(first + Int(inner * 2 / period) + 3) {
            let left = mid.x + CGFloat(i) * period - pose.filmX
            c.opacity = pose.film * 0.85
            c.fill(Path(CGRect(x: left, y: mid.y - fh / 2, width: fw, height: fh)), with: .color(.cInk))
            c.opacity = pose.film
            let band = CGFloat(((i % 5) + 5) % 5) / 5 * 0.6 + 0.15
            c.fill(Path(CGRect(x: left, y: mid.y - fh / 2 + fh * band, width: fw, height: fh * 0.14)), with: .color(.cRed))
        }
        c.opacity = pose.film * 0.6
        let hole: CGFloat = 4.5
        let firstHole = Int(((pose.filmX - inner) / hole).rounded(.down)) - 1
        for j in firstHole..<(firstHole + Int(inner * 2 / hole) + 3) {
            let x = mid.x + CGFloat(j) * hole - pose.filmX
            c.fill(Path(CGRect(x: x, y: mid.y - 15, width: 2, height: 2)), with: .color(.cInk))
            c.fill(Path(CGRect(x: x, y: mid.y + 13, width: 2, height: 2)), with: .color(.cInk))
        }
        // Soft edges, so clips slide in from behind the brackets.
        c.opacity = 1
        c.blendMode = .destinationOut
        for side in [CGFloat(-1), 1] {
            let edge = mid.x + side * inner, inside = mid.x + side * (inner - 8)
            c.fill(Path(CGRect(x: min(edge, inside), y: mid.y - 16, width: 8, height: 32)),
                   with: .linearGradient(Gradient(colors: [.black, .clear]), startPoint: CGPoint(x: edge, y: 0), endPoint: CGPoint(x: inside, y: 0)))
        }
    }

    private func brackets(_ pose: Pose, in ctx: inout GraphicsContext, mid: CGPoint) {
        // Stretched like a band: taller, thinner, and the tips flaring out as if pulled at.
        let style = StrokeStyle(lineWidth: 13 * Self.k * (1 - 0.3 * pose.stretch), lineCap: .round, lineJoin: .round)
        let a = Self.arm * (1 + 0.28 * pose.stretch)
        let flare = 7 * pose.stretch
        for (side, opacity) in [(CGFloat(-1), pose.leftOpacity), (1, pose.rightOpacity)] where opacity > 0 {
            var p = Path()
            p.move(to: CGPoint(x: 12, y: -a - flare)); p.addLine(to: CGPoint(x: -8, y: -a))
            p.addQuadCurve(to: CGPoint(x: -12, y: -a + 4), control: CGPoint(x: -12, y: -a))
            p.addLine(to: CGPoint(x: -12, y: a - 4))
            p.addQuadCurve(to: CGPoint(x: -8, y: a), control: CGPoint(x: -12, y: a))
            p.addLine(to: CGPoint(x: 12, y: a + flare))
            let t = CGAffineTransform(translationX: mid.x + side * pose.spread, y: mid.y)
                .scaledBy(x: -side * Self.k, y: Self.k)
            var c = ctx
            c.opacity = opacity
            c.stroke(p.applying(t), with: .color(pose.colour), style: style)
        }
    }

    static func ease(_ x: Double) -> CGFloat {
        let c = min(1, max(0, x))
        return CGFloat(c * c * (3 - 2 * c))
    }

    static func slam(_ x: Double) -> CGFloat {
        let c = min(1, max(0, x))
        return CGFloat(c * c * c)
    }
}
