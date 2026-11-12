import CoreImage
import Foundation
import ReplayKit

/// Records a screen tour: watches the screen while Kez uses other apps and saves a still each time it settles
/// on something new (or on a fixed interval) into the App Group, Tours/<start time>/frames/.
///
/// The extension has about 50 MB to work in, so frames are checked four times a second at 32×32, and only
/// kept frames are rendered at full size.
final class SampleHandler: RPBroadcastSampleHandler {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()

    private var folder: URL!
    private var start = Date()
    private var frames: [Frame] = []
    private var lastCheck = -1.0
    private var lastKeptTime = -Double.infinity
    private var gate = ChangeGate(change: 0.045, still: 0.012, minGap: 1.0)
    private var interval = 0.0
    private var stopObserver: DarwinObserver?
    private var finishing = false
    private let island = IslandPush()
    private var announced = false
    private var begins = Date()
    /// The newest picture of the screen. iOS only sends one when the screen changes, so on an interval the shutter
    /// takes whatever this is at each tick rather than waiting for a change.
    private var latest: CIImage?
    /// Fires exactly every `interval` from `begins`, so frames land on the beat the Island's ring counts down to.
    private var shutter: DispatchSourceTimer?

    /// Seconds after the broadcast starts before frames are taken (chosen in the app; the Island counts it down).
    private var delay = 3.0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        start = Date()
        let id = String(Int(start.timeIntervalSince1970))
        folder = AppGroup.tours.appending(path: id, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder.appending(path: "frames"), withIntermediateDirectories: true)
        let d = AppGroup.defaults
        interval = d.double(forKey: SharedKey.tourInterval)
        delay = d.object(forKey: SharedKey.tourDelay) as? Double ?? 3

        begins = start.addingTimeInterval(delay)
        d.set(begins.timeIntervalSince1970, forKey: SharedKey.tourBegins)
        d.set(0, forKey: SharedKey.tourCount)
        d.set(false, forKey: SharedKey.stopRequested)
        d.set(id, forKey: SharedKey.activeTour)
        DarwinCenter.post(DarwinCenter.tourChanged)

        stopObserver = DarwinObserver(DarwinCenter.stopTour) { [weak self] in self?.stopFromOutside() }

        if interval > 0 {
            let timer = DispatchSource.makeTimerSource(flags: .strict, queue: DispatchQueue(label: "com.kezlahd.cut.shutter", qos: .userInitiated))
            timer.schedule(wallDeadline: .now() + delay, repeating: interval, leeway: .milliseconds(5))
            timer.setEventHandler { [weak self] in self?.shoot() }
            timer.resume()
            shutter = timer
        }

        // Pops the Island open for a moment with the countdown, then it shrinks back to the ring.
        if delay > 0 {
            island.update(TourState(phase: .countdown, begins: begins, since: start, next: begins, gap: interval),
                          alert: ("Leave Cut now", "First frame in \(TourState.seconds(delay)). Open the app you want to capture."))
        }
    }

    /// The Island's state with `count` frames taken. On an interval the next frame is due on the shutter's beat,
    /// an exact time, so the ring empties at the moment it's taken even if this update reaches the phone late.
    private func state(_ count: Int) -> TourState {
        TourState(phase: .recording, frames: count, begins: begins, since: start,
                  next: interval > 0 ? begins.addingTimeInterval(Double(count) * interval) : nil, gap: interval)
    }

    /// One tick of the shutter: saves the newest picture of the screen as the next frame.
    private func shoot() {
        lock.lock()
        let image = latest, count = frames.count, done = finishing
        lock.unlock()
        guard !done, let image else { return }
        save(image, at: Double(count) * interval)
    }

    private func stopFromOutside() {
        lock.lock(); defer { lock.unlock() }
        guard !finishing else { return }
        finishing = true
        let n = frames.count
        finishBroadcastWithError(NSError(domain: "com.kezlahd.cut", code: 1, userInfo: [
            NSLocalizedDescriptionKey: n == 0 ? "Screen tour stopped. No frames were taken." : "Screen tour saved: \(n) frames. Open Cut to pick them.",
        ]))
    }

    override func broadcastFinished() {
        lock.lock()
        let n = frames.count
        lock.unlock()
        shutter?.cancel()
        island.end(TourState(phase: .saved, frames: n, begins: begins, since: start, gap: interval))
        let d = AppGroup.defaults
        d.set(n, forKey: SharedKey.tourCount)
        d.removeObject(forKey: SharedKey.activeTour)
        d.set(false, forKey: SharedKey.stopRequested)
        DarwinCenter.post(DarwinCenter.tourChanged)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with type: RPSampleBufferType) {
        guard type == .video else { return }
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var image = CIImage(cvPixelBuffer: pixels)
        if let raw = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
           let orientation = CGImagePropertyOrientation(rawValue: raw.uint32Value) {
            image = image.oriented(orientation)
        }
        // On an interval the shutter takes the frames; this only keeps the newest picture ready for it.
        if interval > 0 {
            lock.lock(); latest = image; lock.unlock()
            return
        }

        let t = Date().timeIntervalSince(start) - delay
        guard t >= 0, t - lastCheck >= 0.25 else { return }
        lastCheck = t

        autoreleasepool {
            let keep = gate.shouldKeep(Thumb(image, context: context), at: t)
            if !announced {
                announced = true
                // Frames have started; when the first isn't taken straight away (on change), say so anyway.
                if !keep { island.update(state(0)) }
            }
            guard keep else { return }
            lastKeptTime = t
            save(image, at: t)
        }
    }

    private func save(_ image: CIImage, at time: Double) {
        // Half size is plenty to read a screen and keeps each frame around 150 KB.
        let scaled = image.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let data = context.jpegRepresentation(of: scaled, colorSpace: space,
                                                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.82])
        else { return }
        lock.lock()
        let frame = Frame(id: frames.count, time: time, file: String(format: "%03d.jpg", frames.count))
        frames.append(frame)
        let all = frames
        lock.unlock()
        try? data.write(to: folder.appending(path: "frames/\(frame.file)"))
        try? JSONEncoder().encode(all).write(to: folder.appending(path: "frames.json"), options: .atomic)
        AppGroup.defaults.set(all.count, forKey: SharedKey.tourCount)
        DarwinCenter.post(DarwinCenter.tourChanged)

        // One update per frame: the new tally, and the ring set running to the next beat.
        island.update(state(all.count))
    }
}

/// Matches the app's frame record (Shared/Models.swift isn't compiled into this extension).
struct Frame: Codable {
    var id: Int
    var time: Double
    var file: String
    var kept = true
}
