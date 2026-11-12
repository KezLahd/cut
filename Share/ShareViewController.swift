import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share to Cut: takes a video file or a link, drops it in the Inbox and closes. A link starts its cloud
/// fetch straight away, so the video is usually ready by the time Cut is opened.
enum ShareHandler {
    typealias Outcome = ShareOutcome

    static func handle(_ items: [NSExtensionItem]) async -> Outcome {
        let providers = items.flatMap { $0.attachments ?? [] }
        let text = items.compactMap { $0.attributedContentText?.string }.first { !$0.isEmpty }
        let title = text.flatMap { CloudDispatch.firstLink(in: $0) == nil ? String($0.prefix(80)) : nil }

        // Files first: a shared screen recording or video.
        for p in providers {
            for type in [UTType.movie, .video, .audiovisualContent] where p.hasItemConformingToTypeIdentifier(type.identifier) {
                if (try? await copyVideo(p, type: type, title: title)) != nil { return .video }
            }
        }
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, !url.isFileURL {
                return await addLink(url)
            }
        }
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let s = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String, let url = CloudDispatch.firstLink(in: s) {
                return await addLink(url)
            }
        }
        if let text, let url = CloudDispatch.firstLink(in: text) { return await addLink(url) }
        return .nothing
    }

    private static func write(_ item: InboxItem) throws {
        try JSONEncoder().encode(item).write(to: AppGroup.inbox.appending(path: "\(item.id).json"), options: .atomic)
    }

    private static func newID() -> String { "\(Int(Date.now.timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(4))" }

    private static func addLink(_ url: URL) async -> Outcome {
        var item = InboxItem(id: newID(), link: url.absoluteString, added: .now)
        var outcome = Outcome.link(url)
        if let token = CloudConfig.token,
           let run = try? await CloudDispatch.start(repo: CloudConfig.repo, token: token, link: url.absoluteString, runName: item.id, timeout: 8) {
            item.runID = run
            outcome = .cloud(url)
        }
        do { try write(item) } catch { return .failed("Couldn't save the link.") }
        return outcome
    }

    private static func copyVideo(_ provider: NSItemProvider, type: UTType, title: String?) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, error in
                // The file only exists inside this callback, so copy it now.
                guard let url else { cont.resume(throwing: error ?? CocoaError(.fileNoSuchFile)); return }
                do {
                    let id = newID()
                    let name = "\(id).\(url.pathExtension.isEmpty ? "mov" : url.pathExtension)"
                    try FileManager.default.copyItem(at: url, to: AppGroup.inbox.appending(path: name))
                    try write(InboxItem(id: id, title: title, video: name, added: .now))
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

final class ShareViewController: UIViewController {
    private var host: UIHostingController<ShareScreen>!
    private var closed = false

    override func viewDidLoad() {
        super.viewDidLoad()
        let start = Date.now
        host = UIHostingController(rootView: ShareScreen(start: start, outcome: nil, doneAfter: nil, dismiss: close))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Task { @MainActor in
            let outcome = await ShareHandler.handle(items)
            // The film always rolls for a moment, so a quick save still reads, then the cut and the snap.
            let done = max(PullBrackets.minimumLoad, Date.now.timeIntervalSince(start))
            host.rootView = ShareScreen(start: start, outcome: outcome, doneAfter: done, dismiss: close)
            let wait = done - Date.now.timeIntervalSince(start) + PullBrackets.endAfter + 0.6
            try? await Task.sleep(for: .seconds(wait))
            close()
        }
    }

    private func close() {
        guard !closed else { return }
        closed = true
        extensionContext?.completeRequest(returningItems: nil)
    }
}
