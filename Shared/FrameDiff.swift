import CoreImage
import Foundation

/// A 32×32 greyscale thumbnail, used to tell whether the picture has changed.
struct Thumb {
    static let side = 32
    var pixels: [UInt8]

    init(_ image: CIImage, context: CIContext) {
        let e = image.extent
        let scaled = image.transformed(by: CGAffineTransform(scaleX: CGFloat(Thumb.side) / e.width, y: CGFloat(Thumb.side) / e.height))
            .transformed(by: CGAffineTransform(translationX: -e.minX * CGFloat(Thumb.side) / e.width, y: -e.minY * CGFloat(Thumb.side) / e.height))
        var buffer = [UInt8](repeating: 0, count: Thumb.side * Thumb.side)
        context.render(scaled, toBitmap: &buffer, rowBytes: Thumb.side, bounds: CGRect(x: 0, y: 0, width: Thumb.side, height: Thumb.side),
                       format: .L8, colorSpace: nil)
        pixels = buffer
    }

    /// Mean absolute difference, 0 (identical) to 1.
    func diff(_ other: Thumb) -> Double {
        var total = 0
        for i in 0..<pixels.count { total += abs(Int(pixels[i]) - Int(other.pixels[i])) }
        return Double(total) / Double(pixels.count) / 255
    }
}

/// Decides when a moving picture has settled on something new: it must differ from the last kept frame and
/// have stopped moving (so a scroll or a transition isn't captured half-way).
struct ChangeGate {
    var changeThreshold: Double
    var stillThreshold: Double
    var minGap: Double

    private var lastKept: Thumb?
    private var previous: Thumb?
    private var lastKeptTime = -Double.infinity

    init(change: Double, still: Double, minGap: Double) {
        changeThreshold = change
        stillThreshold = still
        self.minGap = minGap
    }

    mutating func shouldKeep(_ thumb: Thumb, at time: Double) -> Bool {
        defer { previous = thumb }
        guard time - lastKeptTime >= minGap else { return false }
        let changed = lastKept.map { thumb.diff($0) > changeThreshold } ?? true
        let still = previous.map { thumb.diff($0) < stillThreshold } ?? false
        guard changed, still else { return false }
        lastKept = thumb
        lastKeptTime = time
        return true
    }
}
