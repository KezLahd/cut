import Foundation

/// What the Island shows during a screen tour. Kept free of ActivityKit so the broadcast extension can build it
/// and push it through APNs. Times are stored as plain seconds since 1970, so the JSON the extension sends
/// decodes the same way on the phone whatever date format ActivityKit expects.
struct TourState: Codable, Hashable {
    enum Phase: String, Codable { case waiting, countdown, recording, saved }
    var phase: Phase
    var frames: Int = 0
    private var beginsAt: Double?
    private var sinceAt: Double?
    private var nextAt: Double?
    /// True for a moment after each frame is taken.
    var flash = false
    /// Seconds between frames (0 on change), so the ring knows where each countdown began.
    var gap: Double = 0

    init(phase: Phase, frames: Int = 0, begins: Date? = nil, since: Date? = nil, next: Date? = nil, flash: Bool = false, gap: Double = 0) {
        self.phase = phase
        self.frames = frames
        beginsAt = begins?.timeIntervalSince1970
        sinceAt = since?.timeIntervalSince1970
        nextAt = next?.timeIntervalSince1970
        self.flash = flash
        self.gap = gap
    }

    /// "3s", "1 min", "1m 30s".
    static func seconds(_ s: Double) -> String {
        if s < 60 { return "\(Int(s))s" }
        let m = Int(s) / 60, r = Int(s) % 60
        return r == 0 ? "\(m) min" : "\(m)m \(r)s"
    }

    /// When frames start: the countdown runs to it and the clock runs from it.
    var begins: Date? { beginsAt.map(Date.init(timeIntervalSince1970:)) }
    /// When the countdown started, so the timer's range never moves under it.
    var since: Date? { sinceAt.map(Date.init(timeIntervalSince1970:)) }
    /// When the next frame is due on a fixed interval; nil when frames are taken on change.
    var next: Date? { nextAt.map(Date.init(timeIntervalSince1970:)) }
}
