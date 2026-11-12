import SwiftUI

/// What sharing to Cut did.
enum ShareOutcome { case video, link(URL), cloud(URL), nothing, failed(String) }

/// The share sheet, Cut style: the brackets roll film while the link goes off to be fetched, then the cut goes
/// through and they snap shut into the mark. Underneath, where it came from and what happens next.
struct ShareScreen: View {
    var start: Date
    var outcome: ShareOutcome?
    /// Seconds after `start` when the outcome came in.
    var doneAfter: TimeInterval?
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if failed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34, weight: .semibold)).foregroundStyle(Color.cRed)
                    .frame(height: 120)
            } else {
                PullBrackets(pull: PullBrackets.threshold, refreshStart: start, doneAfter: doneAfter, keep: true)
                    .scaleEffect(1.6)
                    .frame(height: 120)
            }
            VStack(spacing: 0) {
                // Always takes its line, so the words don't jump when it appears.
                HStack(spacing: 6) {
                    Image(systemName: kicker?.icon ?? "link").font(.system(size: 11, weight: .bold))
                    Text((kicker?.text ?? " ").uppercased()).font(.mono(11.5, .medium)).tracking(0.8)
                }
                .foregroundStyle(Color.cRed)
                .opacity(kicker == nil ? 0 : 1)
                .padding(.bottom, 10)
                Text(headline)
                    .font(.app(26, .bold)).foregroundStyle(Color.cInk)
                    .contentTransition(.opacity)
                Text(detail)
                    .font(.app(15)).foregroundStyle(Color.cMute)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                Text(link ?? " ")
                        .font(.mono(11.5)).foregroundStyle(Color.cMute.opacity(0.8))
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.top, 16)
            }
            .padding(.horizontal, 36)
            .padding(.top, 14)
            .animation(.snappy(duration: 0.3), value: doneAfter)
            Spacer(minLength: 0)
            Button(action: dismiss) { Text("Done").frame(maxWidth: .infinity) }
                .buttonStyle(SecondaryButtonStyle(height: 48))
                .padding(.horizontal, 36)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cBg.ignoresSafeArea())
    }

    private var failed: Bool {
        switch outcome { case .failed?, .nothing?: true; default: false }
    }

    private var url: URL? {
        switch outcome { case .link(let u)?, .cloud(let u)?: u; default: nil }
    }

    private var link: String? {
        url.map { ($0.host() ?? "").replacingOccurrences(of: "www.", with: "") + $0.path() }
    }

    /// "Instagram · Reel", "TikTok", "YouTube · Short".
    private var kicker: (icon: String, text: String)? {
        switch outcome {
        case .video?: return ("film", "Video")
        case nil, .nothing?, .failed?: return nil
        default: break
        }
        guard let url else { return nil }
        let host = url.host()?.lowercased() ?? "", path = url.path().lowercased()
        let name: String
        if host.contains("instagram") { name = path.contains("/reel") ? "Instagram · Reel" : "Instagram · Post" }
        else if host.contains("tiktok") { name = "TikTok" }
        else if host.contains("youtu") { name = path.contains("/shorts") ? "YouTube · Short" : "YouTube" }
        else if host == "x.com" || host.contains("twitter") { name = "X" }
        else { name = host.replacingOccurrences(of: "www.", with: "") }
        return ("link", name)
    }

    private var headline: String {
        switch outcome {
        case nil: "Sending to Cut"
        case .cloud?: "Cutting in the cloud"
        case .link?: "Saved to Cut"
        case .video?: "Added to Cut"
        case .nothing?: "Nothing to cut"
        case .failed?: "Couldn't add this"
        }
    }

    private var detail: String {
        switch outcome {
        case nil: "One moment."
        case .cloud?: "It'll be waiting in Cut in about a minute, ready for you to pick frames."
        case .link?: "Cut fetches it when you next open it."
        case .video?: "Open Cut to pick your frames."
        case .nothing?: "Share a video, a reel or a screen recording."
        case .failed(let why)?: why
        }
    }
}

