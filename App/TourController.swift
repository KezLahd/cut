import ActivityKit
import AVFoundation
import Observation
import ReplayKit
import SwiftUI
import UIKit

/// Starts and stops a screen tour. iOS insists on its own "Start Broadcast" sheet every time; this opens it,
/// runs the Live Activity, and listens for the broadcast extension.
///
/// The extension can't update a Live Activity (it belongs to the app), so while a tour is on the app keeps
/// itself running with silent audio and moves the Island along itself: countdown, then the frame count.
@MainActor @Observable
final class TourController {
    static let extensionID = "com.kezlahd.cut.broadcast"

    /// 0 means on change; then half a second, every second to 10, and wider steps up to 2 minutes.
    static let intervals: [Double] = [0, 0.5] + (1...10).map(Double.init) + [12, 15, 20, 25, 30, 40, 45, 60, 90, 120]
    /// Every second to 10, then wider steps up to 5 minutes, for signing in or getting to the right screen.
    static let delays: [Double] = (0...10).map(Double.init) + [12, 15, 20, 25, 30, 40, 45, 60, 75, 90, 120, 180, 300]

    /// "0.5s", "8s", "1 min", "1m 30s".
    static func duration(_ s: Double) -> String {
        if s < 60 { return Mode.seconds(s) }
        let m = Int(s) / 60, r = Int(s) % 60
        return r == 0 ? "\(m) min" : "\(m)m \(r)s"
    }

    private(set) var recording = AppGroup.defaults.string(forKey: SharedKey.activeTour) != nil
    private(set) var frames = AppGroup.defaults.integer(forKey: SharedKey.tourCount)
    private(set) var begins: Date?

    /// Seconds between frames; 0 means when the screen changes.
    var interval: Double {
        didSet { AppGroup.defaults.set(interval, forKey: SharedKey.tourInterval) }
    }
    /// Seconds from Start Broadcast to the first frame.
    var delay: Double {
        didSet { AppGroup.defaults.set(delay, forKey: SharedKey.tourDelay) }
    }

    @ObservationIgnored weak var picker: RPSystemBroadcastPickerView?
    @ObservationIgnored private var observer: DarwinObserver?
    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored private let awake = KeepAwake()
    @ObservationIgnored private var switchToRecording: Task<Void, Never>?
    @ObservationIgnored private var waiting: Task<Void, Never>?

    init() {
        let d = AppGroup.defaults
        interval = d.object(forKey: SharedKey.tourInterval) as? Double ?? 2
        delay = d.object(forKey: SharedKey.tourDelay) as? Double ?? 3
        observer = DarwinObserver(DarwinCenter.tourChanged) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        if recording { awake.start(); refresh() }
    }

    func refresh() {
        let d = AppGroup.defaults
        let wasRecording = recording
        recording = d.string(forKey: SharedKey.activeTour) != nil
        frames = d.integer(forKey: SharedKey.tourCount)
        let at = d.double(forKey: SharedKey.tourBegins)
        begins = at > 0 ? Date(timeIntervalSince1970: at) : nil

        if recording {
            waiting?.cancel()
            awake.start()
            pushState()
        } else if wasRecording {
            switchToRecording?.cancel()
            unflash?.cancel()
            lastPushed = nil; lastFrames = 0; since = nil
            AppGroup.defaults.removeObject(forKey: SharedKey.tourPushToken)
            let n = frames, b = begins
            Task {
                await TourActivity.end(.init(phase: .saved, frames: n, begins: b))
                awake.stop()
            }
            onFinished?()
        }
    }

    @ObservationIgnored private var lastPushed: TourAttributes.ContentState?
    @ObservationIgnored private var lastFrames = 0
    @ObservationIgnored private var since: Date?
    @ObservationIgnored private var unflash: Task<Void, Never>?

    /// Puts the Island in step with the tour: counting down until `begins`, then a flash each time a frame lands,
    /// the time to the next one, and the tally. Identical states aren't sent again, so the timers never restart.
    private func pushState() {
        // With a push token, the broadcast extension moves the Island along itself (see Broadcast/IslandPush.swift).
        guard let begins, AppGroup.defaults.string(forKey: SharedKey.tourPushToken) == nil else { return }
        let gap = AppGroup.defaults.double(forKey: SharedKey.tourInterval)
        // The broadcast started `delay` before `begins`: a fixed start for the countdown's range.
        if since == nil { since = begins.addingTimeInterval(-max(0, AppGroup.defaults.double(forKey: SharedKey.tourDelay))) }
        if Date.now < begins {
            send(.init(phase: .countdown, frames: 0, begins: begins, since: since, next: begins, gap: gap))
            switchToRecording?.cancel()
            switchToRecording = Task {
                try? await Task.sleep(for: .seconds(begins.timeIntervalSinceNow))
                guard !Task.isCancelled, recording else { return }
                // The first frame is due now; the extension takes it within a quarter of a second.
                send(.init(phase: .recording, frames: frames, begins: begins, since: since, next: gap > 0 ? .now.addingTimeInterval(0.3) : nil, gap: gap))
            }
            return
        }
        let shot = frames > lastFrames
        lastFrames = frames
        let next: Date? = gap > 0 ? (shot ? .now.addingTimeInterval(gap) : lastPushed?.next) : nil
        var state = TourAttributes.ContentState(phase: .recording, frames: frames, begins: begins, since: since, next: next, gap: gap)
        if shot {
            state.flash = true
            send(state)
            unflash?.cancel()
            let settled = TourAttributes.ContentState(phase: .recording, frames: frames, begins: begins, since: since, next: next, gap: gap)
            unflash = Task {
                try? await Task.sleep(for: .seconds(0.45))
                guard !Task.isCancelled, recording else { return }
                send(settled)
            }
        } else {
            send(state)
        }
    }

    private func send(_ state: TourAttributes.ContentState) {
        guard state != lastPushed else { return }
        lastPushed = state
        Task { await TourActivity.update(state) }
    }

    func start() {
        AppGroup.defaults.set(interval, forKey: SharedKey.tourInterval)
        AppGroup.defaults.set(delay, forKey: SharedKey.tourDelay)
        AppGroup.defaults.set(false, forKey: SharedKey.stopRequested)
        lastPushed = nil; lastFrames = 0; since = nil
        AppGroup.defaults.removeObject(forKey: SharedKey.tourPushToken)
        awake.start()
        waiting?.cancel()
        waiting = Task {
            await TourActivity.end(nil)
            if ActivityAuthorizationInfo().areActivitiesEnabled {
                // A push token lets the broadcast extension update the Island once Cut is in the background.
                if let activity = try? Activity.request(attributes: TourAttributes(),
                                                        content: ActivityContent(state: .init(phase: .waiting), staleDate: nil),
                                                        pushType: .token) {
                    Task.detached {
                        for await token in activity.pushTokenUpdates {
                            AppGroup.defaults.set(token.map { String(format: "%02x", $0) }.joined(), forKey: SharedKey.tourPushToken)
                        }
                    }
                }
            }
            // Tap the system picker's own button: that's what opens the Start Broadcast sheet.
            picker?.subviews.compactMap { $0 as? UIButton }.first?.sendActions(for: .allTouchEvents)
            // No broadcast a while after the sheet opened: it was cancelled, so put everything away.
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, !recording else { return }
            await TourActivity.end(nil)
            awake.stop()
        }
    }

    func stop() {
        AppGroup.defaults.set(true, forKey: SharedKey.stopRequested)
        DarwinCenter.post(DarwinCenter.stopTour)
    }
}

/// Plays silence, mixed with whatever else is playing, so iOS keeps Cut running in the background
/// while a tour is on. Stops as soon as the tour ends.
@MainActor
final class KeepAwake {
    private var player: AVAudioPlayer?

    func start() {
        guard player == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        guard let p = try? AVAudioPlayer(data: Self.silence) else { return }
        p.numberOfLoops = -1
        p.volume = 0
        p.play()
        player = p
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// One second of 8 kHz mono 16-bit silence as a WAV.
    private static let silence: Data = {
        let rate: UInt32 = 8000, samples = rate
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + samples * 2)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(samples * 2)
        d.append(Data(count: Int(samples * 2)))
        return d
    }()
}

/// The system broadcast picker, kept tiny and invisible; TourController taps it.
struct BroadcastPicker: UIViewRepresentable {
    var controller: TourController

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let view = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.preferredExtension = TourController.extensionID
        view.showsMicrophoneButton = false
        view.alpha = 0.011
        controller.picker = view
        return view
    }

    func updateUIView(_ view: RPSystemBroadcastPickerView, context: Context) {
        controller.picker = view
    }
}
