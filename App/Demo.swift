#if DEBUG
import SwiftUI
import UIKit

/// Simulator only: CUT_DEMO=1 fills an empty Cut with two sample cuts so the screens can be checked without a
/// phone. CUT_SHEET=link|tour opens a sheet, CUT_OPEN=1 opens the newest cut.
extension Store {
    func seedDemoIfAsked() {
        let env = ProcessInfo.processInfo.environment
        defer { if env["CUT_DEMO"] != nil, let open = env["CUT_OPEN"] { path = [open == "tour" ? "demo-0" : "demo-1"] } }
        guard env["CUT_DEMO"] != nil, cuts.isEmpty else { return }
        // Made-up content only: a reel about lighting a room, a screen tour of a recipe app, and a clip from Photos.
        let samples: [(String, String?, CutSet.Source, String?, Double, Int, TimeInterval)] = [
            ("Screen tour", "Wed 5:39 pm", .tour, nil, 41, 9, 0),
            ("Five ways to light a small room", "@roomlight.studio", .link, "https://www.instagram.com/reel/demo/", 58, 14, -86_400),
            ("Kitchen before the build", nil, .video, nil, 84, 11, -3 * 86_400),
        ]
        for (n, s) in samples.enumerated() {
            let id = "demo-\(n)"
            let dir = folder(id).appending(path: "frames")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var frames: [Frame] = []
            for i in 0..<s.5 {
                let img = s.2 == .tour ? Self.demoScreen(i) : Self.demoScene(i, of: s.5, warm: s.2 == .link)
                let file = String(format: "%03d.jpg", i)
                try? img.jpegData(compressionQuality: 0.85)?.write(to: dir.appending(path: file))
                frames.append(Frame(id: i, time: Double(i) * s.4 / Double(s.5), file: file, kept: i % 5 != 3))
            }
            var c = CutSet(id: id, title: s.0, byline: s.1, source: s.2, link: s.3, created: Date.now.addingTimeInterval(s.6),
                           duration: s.4, mode: s.2 == .tour ? .scene : .every(2), frames: frames, state: .ready)
            switch s.2 {
            case .tour:
                c.title = "Saving a recipe for the weekend"; c.described = true
                c.summary = "Browsing a recipe app, opening a lemon pasta, then adding it to the weekend list."
            case .link:
                c.video = "demo.mov"; c.described = true
                c.post = Post(handle: "@roomlight.studio", name: "Room Light Studio",
                              caption: "You don't need a bigger room, you need better light. Save this for your next rearrange. #interiors #lighting #smallspaces",
                              posted: Date.now.addingTimeInterval(-3 * 86_400).timeIntervalSince1970, views: 1_240_000, likes: 84_300, comments: 312)
            case .video:
                c.video = "demo.mov"
            }
            cuts.append(c)
            if let data = try? JSONEncoder().encode(c) { try? data.write(to: folder(id).appending(path: "cut.json")) }
        }
    }

    /// A made-up video frame: a room in soft light, with the reel's own heading on screen.
    private static func demoScene(_ i: Int, of n: Int, warm: Bool) -> UIImage {
        let size = CGSize(width: 540, height: 960)
        let tips = ["Bounce it off the ceiling", "Three heights, not one", "Warm bulbs after dark", "Mirror opposite the window",
                    "Light the corners", "Dimmers everywhere", "Hide the source"]
        return UIGraphicsImageRenderer(size: size).image { r in
            let cg = r.cgContext
            let t = CGFloat(i) / CGFloat(max(n - 1, 1))
            let top = warm ? UIColor(hue: 0.08 + 0.03 * t, saturation: 0.35, brightness: 0.92, alpha: 1)
                           : UIColor(hue: 0.55 - 0.05 * t, saturation: 0.18, brightness: 0.86, alpha: 1)
            let bottom = warm ? UIColor(hue: 0.05, saturation: 0.55, brightness: 0.38, alpha: 1)
                              : UIColor(hue: 0.08, saturation: 0.3, brightness: 0.42, alpha: 1)
            let g = CGGradient(colorsSpace: nil, colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            // A lamp's glow moving across the room, a floor line and a sofa.
            let lx = 110 + 320 * (0.5 + 0.5 * sin(Double(i) * 0.9)), ly = 360.0 + 60 * cos(Double(i))
            let glow = CGGradient(colorsSpace: nil, colors: [UIColor(white: 1, alpha: 0.75).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
            cg.drawRadialGradient(glow, startCenter: CGPoint(x: lx, y: ly), startRadius: 0, endCenter: CGPoint(x: lx, y: ly), endRadius: 230, options: [])
            UIColor(white: 0, alpha: 0.18).setFill(); cg.fill(CGRect(x: 0, y: 700, width: size.width, height: 260))
            UIColor(hue: warm ? 0.6 : 0.33, saturation: 0.25, brightness: 0.45, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 70, y: 610, width: 400, height: 140), cornerRadius: 34).fill()
            UIColor(white: 1, alpha: 0.9).setFill()
            UIBezierPath(roundedRect: CGRect(x: lx - 16, y: ly + 40, width: 32, height: 250), cornerRadius: 8).fill()
            guard warm else { return }
            let shadow = NSShadow(); shadow.shadowColor = UIColor(white: 0, alpha: 0.45); shadow.shadowBlurRadius = 8
            let head: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 40, weight: .heavy), .foregroundColor: UIColor.white, .shadow: shadow]
            let line: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1), .shadow: shadow]
            let p = NSMutableParagraphStyle(); p.alignment = .center
            NSAttributedString(string: "5 ways to light\na small room", attributes: head.merging([.paragraphStyle: p]) { $1 })
                .draw(in: CGRect(x: 20, y: 110, width: 500, height: 110))
            NSAttributedString(string: "\(i % 5 + 1). \(tips[i % tips.count])", attributes: line.merging([.paragraphStyle: p]) { $1 })
                .draw(in: CGRect(x: 20, y: 236, width: 500, height: 44))
        }
    }

    /// A made-up app screen for the screen tour: a recipe list, scrolled a little further each frame.
    private static func demoScreen(_ i: Int) -> UIImage {
        let size = CGSize(width: 540, height: 1170)
        let names = ["Lemon pasta", "Miso aubergine", "Green curry", "Crispy gnocchi", "Tomato galette", "Chilli eggs",
                     "Peach salad", "Brown butter cake", "Herb rice", "Smash burgers", "Corn soup", "Fig toast"]
        return UIGraphicsImageRenderer(size: size).image { r in
            UIColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1).setFill(); r.fill(CGRect(origin: .zero, size: size))
            let title: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 44, weight: .bold), .foregroundColor: UIColor.black]
            let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: UIColor.black]
            let mute: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 21), .foregroundColor: UIColor.gray]
            if i >= 6 {
                // Opened one: a big photo and the method.
                let hue = 0.12
                UIColor(hue: hue, saturation: 0.55, brightness: 0.9, alpha: 1).setFill(); r.fill(CGRect(x: 0, y: 0, width: 540, height: 520))
                UIColor(hue: 0.3, saturation: 0.5, brightness: 0.55, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: 120, y: 140, width: 300, height: 260)).fill()
                NSAttributedString(string: "Lemon pasta", attributes: title).draw(at: CGPoint(x: 32, y: 560))
                NSAttributedString(string: "20 min · serves 2", attributes: mute).draw(at: CGPoint(x: 32, y: 622))
                for k in 0..<5 {
                    UIColor(white: 0.85, alpha: 1).setFill()
                    r.fill(CGRect(x: 32, y: 690 + CGFloat(k) * 52, width: CGFloat(420 - (k * 37) % 120), height: 18))
                }
                let added = i >= 8
                (added ? UIColor(red: 0.2, green: 0.6, blue: 0.35, alpha: 1) : UIColor.black).setFill()
                UIBezierPath(roundedRect: CGRect(x: 32, y: 1020, width: 476, height: 84), cornerRadius: 42).fill()
                let btn: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: UIColor.white]
                let s = NSAttributedString(string: added ? "On the weekend list" : "Add to weekend", attributes: btn)
                s.draw(at: CGPoint(x: 270 - s.size().width / 2, y: 1046))
                return
            }
            NSAttributedString(string: "Recipes", attributes: title).draw(at: CGPoint(x: 32, y: 120))
            let shift = CGFloat(i) * 70
            for k in 0..<names.count {
                let y = 220 + CGFloat(k) * 150 - shift
                guard y > 190, y < 1150 else { continue }
                UIColor(hue: CGFloat(k) * 0.083, saturation: 0.45, brightness: 0.85, alpha: 1).setFill()
                UIBezierPath(roundedRect: CGRect(x: 32, y: y, width: 120, height: 120), cornerRadius: 20).fill()
                NSAttributedString(string: names[k], attributes: body).draw(at: CGPoint(x: 176, y: y + 26))
                NSAttributedString(string: "\(15 + k * 5) min", attributes: mute).draw(at: CGPoint(x: 176, y: y + 66))
            }
        }
    }
}
#endif

#if DEBUG
import ActivityKit

/// Simulator only: CUT_ISLAND=1 runs a fake tour in the Dynamic Island (countdown, then a frame every 3 s with
/// the flash) so the Island can be checked without recording. CUT_ISLAND=2 adds a second activity, the way the
/// system's own screen-recording dot shares the Island on a phone.
enum IslandDemo {
    @MainActor static func runIfAsked() {
        guard let mode = ProcessInfo.processInfo.environment["CUT_ISLAND"] else { return }
        Task {
            for a in Activity<TourAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
            let since = Date.now, begins = since.addingTimeInterval(6)
            var state = TourAttributes.ContentState(phase: .countdown, frames: 0, begins: begins, since: since, next: begins)
            let main = try? Activity.request(attributes: TourAttributes(), content: .init(state: state, staleDate: nil))
            if mode == "2" {
                _ = try? Activity.request(attributes: TourAttributes(), content: .init(state: .init(phase: .waiting), staleDate: nil))
            }
            try? await Task.sleep(for: .seconds(6))
            for n in 1...40 {
                state = .init(phase: .recording, frames: n, begins: begins, since: since, next: .now.addingTimeInterval(3), flash: true, gap: 3)
                await main?.update(.init(state: state, staleDate: nil))
                try? await Task.sleep(for: .seconds(0.45))
                state.flash = false
                await main?.update(.init(state: state, staleDate: nil))
                try? await Task.sleep(for: .seconds(2.55))
            }
        }
    }
}
#endif
