import Foundation
import FoundationModels
import Vision

/// Names a cut from what's in it, all on the phone: Vision reads the text off a spread of frames, then Apple's
/// on-device model turns that into a short title and one line about it. A screen tour goes by its screens; a reel
/// by its on-screen text and its caption, since a caption is often a joke or hashtags that don't say what the video
/// is. Nothing leaves the phone. Where the model isn't available the cut keeps the name it had.
enum TourNamer {
    struct Result {
        var title: String
        var summary: String
    }

    @Generable
    struct Named {
        @Guide(description: "A short title, 2 to 6 words, sentence case, saying what it is about. No quotes, no hashtags, no emoji, no full stop.")
        var title: String
        @Guide(description: "One plain sentence, under 20 words, saying what it shows.")
        var summary: String
    }

    /// A screen tour: pass only its frames. A video from a link: pass its caption too.
    enum Kind { case tour, video }

    static func name(frames: [URL], kind: Kind = .tour, caption: String? = nil) async -> Result? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let (text, heading) = await read(frames)
        let caption = caption?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(800) ?? ""
        guard text.count + caption.count > 20 else { return nil }
        let isVideo = kind == .video
        let session = LanguageModelSession(instructions: isVideo ? """
            You title short social videos (reels). You get the creator's caption and the text read off a few frames, \
            in order. Captions are often jokes, reactions or hashtags that don't say what the video is; the on-screen \
            text usually shows the real topic. Title what the video is actually about.
            """ : """
            You name screen recordings made on an iPhone. You get the text read off a few of its screens, in order. \
            Status bar text, clock times and battery levels are noise. Name what the person was looking at.
            """)
        let prompt = isVideo ? "Caption:\n\(caption)\n\nText on the frames:\n\(text.isEmpty ? "(none)" : text)" : "Text on the screens:\n\(text)"
        let reply = try? await session.respond(to: prompt, generating: Named.self)
        let summary = reply?.content.summary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // A reel that puts its own title on screen ("20 AI Design Trends") goes by that, word for word.
        if isVideo, let heading { return Result(title: heading, summary: summary) }
        guard let reply else { return nil }
        let title = reply.content.title.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\".")))
        guard !title.isEmpty else { return nil }
        return Result(title: String(title.prefix(60)), summary: summary)
    }

    /// Up to six frames spread across the cut, each screen's lines once, capped to fit the model's window; and the
    /// heading, if there is one: the biggest text that stays on screen in most of the frames.
    private static func read(_ frames: [URL]) async -> (text: String, heading: String?) {
        let picks = frames.count <= 6 ? frames : (0..<6).map { frames[$0 * (frames.count - 1) / 5] }
        var seen = Set<String>(), screens: [String] = []
        var heights: [String: (text: String, frames: Int, height: Double)] = [:]
        for url in picks {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            guard let found = try? await request.perform(on: url) else { continue }
            var here = Set<String>()
            for o in found {
                guard let line = o.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces) else { continue }
                let key = line.lowercased()
                guard here.insert(key).inserted else { continue }
                let h = Double(o.boundingBox.height)
                let was = heights[key]
                heights[key] = (line, (was?.frames ?? 0) + 1, max(was?.height ?? 0, h))
            }
            let lines = found.compactMap { $0.topCandidates(1).first?.string }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count > 2 && !$0.allSatisfy { $0.isNumber || $0 == ":" || $0 == "%" || $0 == " " } && seen.insert($0.lowercased()).inserted }
            if !lines.isEmpty { screens.append(lines.joined(separator: " · ")) }
        }
        let needed = max(2, (picks.count + 1) / 2)
        let heading = heights.values
            .filter { $0.frames >= needed && $0.text.split(separator: " ").count >= 2 && $0.text.count <= 60
                && $0.text.contains(where: \.isLetter) }
            .max { $0.height < $1.height }?.text
        return (String(screens.joined(separator: "\n---\n").prefix(2400)), heading)
    }
}
