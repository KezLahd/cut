import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Pulls stills out of a video file: one every N seconds, or one each time the picture settles on something new.
enum Extractor {
    static let maxFrames = 120

    /// Writes frames/NNN.jpg into `folder` and reports each frame as it lands.
    static func run(video: URL, mode: Mode, into folder: URL,
                    onFrame: @escaping @MainActor (Frame, Double) -> Void) async throws -> (frames: [Frame], duration: Double) {
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw CutError("This video has no length.") }

        let frames = folder.appending(path: "frames", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: frames)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)

        let full = AVAssetImageGenerator(asset: asset)
        full.appliesPreferredTrackTransform = true
        full.maximumSize = CGSize(width: 1600, height: 1600)
        full.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        full.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

        var out: [Frame] = []
        func keep(_ image: CGImage, at time: Double) async throws {
            let frame = Frame(id: out.count, time: time, file: String(format: "%03d.jpg", out.count))
            try writeJPEG(image, to: frames.appending(path: frame.file))
            out.append(frame)
            await onFrame(frame, min(1, time / duration))
        }

        switch mode {
        case .every(let step):
            var t = 0.0
            while t < duration, out.count < maxFrames {
                try Task.checkCancellation()
                let (image, _) = try await full.image(at: CMTime(seconds: t, preferredTimescale: 600))
                try await keep(image, at: t)
                t += max(0.25, step)
            }
        case .scene:
            let small = AVAssetImageGenerator(asset: asset)
            small.appliesPreferredTrackTransform = true
            small.maximumSize = CGSize(width: 96, height: 96)
            small.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
            small.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
            let context = CIContext(options: [.cacheIntermediates: false])
            var gate = ChangeGate(change: 0.08, still: 0.025, minGap: 0.5)
            var t = 0.0
            while t < duration, out.count < maxFrames {
                try Task.checkCancellation()
                if let (thumbImage, _) = try? await small.image(at: CMTime(seconds: t, preferredTimescale: 600)),
                   gate.shouldKeep(Thumb(CIImage(cgImage: thumbImage), context: context), at: t) {
                    let (image, _) = try await full.image(at: CMTime(seconds: t, preferredTimescale: 600))
                    try await keep(image, at: t)
                }
                t += 0.25
            }
            if out.isEmpty {  // a single unchanging shot: keep one frame from the middle
                let (image, _) = try await full.image(at: CMTime(seconds: duration / 2, preferredTimescale: 600))
                try await keep(image, at: duration / 2)
            }
        }
        return (out, duration)
    }

    static func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.85) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CutError("Couldn't save a frame.")
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CutError("Couldn't save a frame.") }
    }
}

struct CutError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
