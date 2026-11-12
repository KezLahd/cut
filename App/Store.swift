import Foundation
import Observation
import SwiftUI

/// All cuts, kept as folders in the App Group container (Cuts/<id>/cut.json, source video, frames/).
@MainActor @Observable
final class Store {
    var cuts: [CutSet] = []
    /// 0…1 while a cut is being made.
    var progress: [String: Double] = [:]
    /// Navigation path of cut ids.
    var path: [String] = []
    var alert: String?
    /// Tours being read for a name.
    var describing: Set<String> = []

    @ObservationIgnored private var work: [String: Task<Void, Never>] = [:]

    init() {
        load()
        loadDeleted()
        #if DEBUG
        seedDemoIfAsked()
        IslandDemo.runIfAsked()
        #endif
        for cut in cuts where cut.state == .cutting || cut.state == .fetching { resume(cut) }
        for cut in cuts where cut.source == .tour && cut.described != true { describe(cut.id) }
        for cut in cuts where cut.source == .link && cut.post == nil && cut.state == .ready { refreshDetails(cut.id) }
        // Version 2 of the namer takes a reel's on-screen title, so links named before it are named again once.
        let renameAll = UserDefaults.standard.integer(forKey: "namerVersion") < 2
        UserDefaults.standard.set(2, forKey: "namerVersion")
        for cut in cuts where cut.source == .link && cut.post != nil && cut.state == .ready && (renameAll || cut.described != true) {
            describe(cut.id)
        }
    }

    /// Reads a cut's frames on the phone and gives it a name and a line about it (see TourNamer): a tour from its
    /// screens, a link from its frames and caption, since the caption alone often doesn't say what the video is.
    func describe(_ id: String) {
        guard let cut = cut(id), cut.source != .video, !describing.contains(id) else { return }
        describing.insert(id)
        let urls = cut.frames.map { url($0, in: cut) }
        let kind: TourNamer.Kind = cut.source == .tour ? .tour : .video
        let caption = cut.post?.caption
        Task {
            let named = await TourNamer.name(frames: urls, kind: kind, caption: caption)
            describing.remove(id)
            update(id) {
                if let named { $0.title = named.title; $0.summary = named.summary }
                $0.described = true
            }
        }
    }

    /// Fetches a link again just for who posted it and what it says (links cut before Cut kept those), keeping the
    /// frames as they are.
    func refreshDetails(_ id: String) {
        guard let cut = cut(id), let link = cut.link.flatMap(URL.init(string:)), let fetcher = CloudFetcher.configured,
              !describing.contains(id) else { return }
        describing.insert(id)
        let scratch = FileManager.default.temporaryDirectory.appending(path: "details-\(id)", directoryHint: .isDirectory)
        Task {
            try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let result = try? await fetcher.fetch(link, runID: nil, name: "\(id)-details", into: scratch)
            describing.remove(id)
            if let post = result?.post {
                update(id) { $0.post = post; $0.byline = post.handle }
                if self.cut(id)?.described != true { describe(id) }
            }
        }
    }

    func rename(_ id: String, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        update(id) { $0.title = t.isEmpty ? ($0.source == .tour ? "Screen tour" : $0.title) : t }
    }

    // MARK: Settings

    static var defaultMode: Mode {
        let d = UserDefaults.standard
        if d.bool(forKey: "defaultScene") { return .scene }
        let s = d.double(forKey: "defaultInterval")
        return .every(s > 0 ? s : 2)
    }

    // MARK: Files

    func folder(_ id: String) -> URL { AppGroup.cuts.appending(path: id, directoryHint: .isDirectory) }
    func url(_ frame: Frame, in cut: CutSet) -> URL { folder(cut.id).appending(path: "frames/\(frame.file)") }
    func cut(_ id: String) -> CutSet? { cuts.first { $0.id == id } }

    private func load() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: AppGroup.cuts, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        cuts = dirs.compactMap { dir in
            (try? Data(contentsOf: dir.appending(path: "cut.json"))).flatMap { try? decoder.decode(CutSet.self, from: $0) }
        }.sorted { $0.created > $1.created }
    }

    private func save(_ cut: CutSet) {
        try? FileManager.default.createDirectory(at: folder(cut.id), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cut) { try? data.write(to: folder(cut.id).appending(path: "cut.json"), options: .atomic) }
    }

    private func update(_ id: String, _ change: (inout CutSet) -> Void) {
        guard let i = cuts.firstIndex(where: { $0.id == id }) else { return }
        change(&cuts[i])
        save(cuts[i])
    }

    private static func newID() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: .now) + "-" + UUID().uuidString.prefix(4)
    }

    // MARK: Adding

    /// A video file from Photos, the share sheet or a fetch. `move` takes ownership of the file.
    @discardableResult
    func addVideo(at url: URL, title: String?, byline: String? = nil, move: Bool) -> String {
        let id = Self.newID()
        try? FileManager.default.createDirectory(at: folder(id), withIntermediateDirectories: true)
        let name = "source." + (url.pathExtension.isEmpty ? "mov" : url.pathExtension.lowercased())
        let dest = folder(id).appending(path: name)
        do {
            if move { try FileManager.default.moveItem(at: url, to: dest) } else { try FileManager.default.copyItem(at: url, to: dest) }
        } catch {
            alert = "Couldn't read that video."
            return id
        }
        let cut = CutSet(id: id, title: title ?? "Video", byline: byline ?? Self.dayStamp(.now), source: .video, created: .now,
                         mode: Self.defaultMode, video: name, state: .cutting)
        cuts.insert(cut, at: 0)
        save(cut)
        startCutting(id)
        return id
    }

    /// A reel or video link: fetched by the cloud workflow, then cut.
    @discardableResult
    func addLink(_ link: URL, title: String? = nil, runID: Int? = nil) -> String {
        let id = Self.newID()
        let site = CutSet.siteName(link.absoluteString) ?? "Link"
        let cut = CutSet(id: id, title: title ?? (site == "Link" ? "Link" : "\(site) post"),
                         byline: nil, source: .link, link: link.absoluteString, created: .now, mode: Self.defaultMode, state: .fetching, runID: runID)
        cuts.insert(cut, at: 0)
        save(cut)
        fetch(id)
        return id
    }

    private func resume(_ cut: CutSet) {
        if cut.state == .fetching { fetch(cut.id) } else { startCutting(cut.id) }
    }

    private func fetch(_ id: String) {
        guard let cut = cut(id), let link = cut.link.flatMap(URL.init(string:)) else { return }
        guard let fetcher = CloudFetcher.configured else {
            update(id) { $0.state = .failed("Links need cloud fetch. Add your GitHub token in Settings, then tap Try again.") }
            return
        }
        work[id] = Task {
            do {
                let result = try await fetcher.fetch(link, runID: cut.runID, name: id, into: folder(id))
                update(id) {
                    $0.video = result.video.lastPathComponent
                    if let t = result.title { $0.title = t }
                    $0.byline = result.byline
                    $0.post = result.post
                    $0.runID = nil
                    $0.state = .cutting
                }
                startCutting(id)
            } catch is CancellationError {
            } catch {
                update(id) { $0.state = .failed(error.localizedDescription); $0.runID = nil }
            }
        }
    }

    func retry(_ id: String) {
        guard let cut = cut(id) else { return }
        if cut.link != nil {
            // A link always starts over from the fetch: a video that failed to cut may be the problem.
            if let video = cut.video { try? FileManager.default.removeItem(at: folder(id).appending(path: video)) }
            update(id) { $0.video = nil; $0.frames = []; $0.runID = nil; $0.state = .fetching }
            fetch(id)
        } else {
            update(id) { $0.state = .cutting }
            startCutting(id)
        }
    }

    // MARK: Cutting

    func recut(_ id: String, mode: Mode) {
        guard let cut = cut(id), cut.mode != mode, cut.video != nil else { return }
        work[id]?.cancel()
        update(id) { $0.mode = mode; $0.frames = []; $0.state = .cutting }
        startCutting(id)
    }

    private func startCutting(_ id: String) {
        guard let cut = cut(id), let video = cut.video else { return }
        work[id]?.cancel()
        update(id) { $0.frames = [] }
        progress[id] = 0
        let source = folder(id).appending(path: video)
        let mode = cut.mode
        work[id] = Task {
            do {
                let result = try await Extractor.run(video: source, mode: mode, into: folder(id)) { [weak self] frame, p in
                    guard let self, !Task.isCancelled else { return }
                    if let i = self.cuts.firstIndex(where: { $0.id == id }) { self.cuts[i].frames.append(frame) }
                    self.progress[id] = p
                }
                update(id) { $0.frames = result.frames; $0.duration = result.duration; $0.state = .ready }
                if let cut = self.cut(id), cut.source == .link, cut.described != true { describe(id) }
            } catch is CancellationError {
            } catch {
                // A fetched video that won't open is dropped, so Try again fetches it fresh rather than failing on it again.
                if let cut = self.cut(id), cut.link != nil, let video = cut.video {
                    try? FileManager.default.removeItem(at: folder(id).appending(path: video))
                    update(id) {
                        $0.video = nil; $0.frames = []
                        $0.state = .failed("The video that came back couldn't be opened. Try again fetches it fresh.")
                    }
                } else {
                    update(id) { $0.state = .failed("Couldn't open this video. It may be in a format the iPhone can't read.") }
                }
            }
            progress[id] = nil
        }
    }

    // MARK: Picking

    func toggle(_ frame: Frame, in id: String) {
        update(id) { cut in
            if let i = cut.frames.firstIndex(where: { $0.id == frame.id }) { cut.frames[i].kept.toggle() }
        }
    }

    func setAll(_ kept: Bool, in id: String) {
        update(id) { cut in for i in cut.frames.indices { cut.frames[i].kept = kept } }
    }

    /// Moves a cut to Recently deleted, where it stays 30 days.
    func delete(_ id: String) {
        work[id]?.cancel()
        guard let cut = cut(id) else { return }
        cuts.removeAll { $0.id == id }
        path.removeAll { $0 == id }
        let fm = FileManager.default
        try? fm.createDirectory(at: AppGroup.deleted, withIntermediateDirectories: true)
        let dest = AppGroup.deleted.appending(path: id, directoryHint: .isDirectory)
        try? fm.removeItem(at: dest)
        if (try? fm.moveItem(at: folder(id), to: dest)) != nil {
            try? Data(ISO8601DateFormatter().string(from: .now).utf8).write(to: dest.appending(path: ".deleted-at"))
            deleted.insert((cut, .now), at: 0)
        }
    }

    static let keepDeletedFor: TimeInterval = 30 * 86_400
    private(set) var deleted: [(cut: CutSet, at: Date)] = []

    func deletedURL(_ frame: Frame, in cut: CutSet) -> URL {
        AppGroup.deleted.appending(path: "\(cut.id)/frames/\(frame.file)")
    }

    func restore(_ id: String) {
        guard let item = deleted.first(where: { $0.cut.id == id }) else { return }
        let src = AppGroup.deleted.appending(path: id, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: src.appending(path: ".deleted-at"))
        guard (try? FileManager.default.moveItem(at: src, to: folder(id))) != nil else { return }
        deleted.removeAll { $0.cut.id == id }
        cuts.append(item.cut)
        cuts.sort { $0.created > $1.created }
    }

    func deleteForever(_ id: String) {
        try? FileManager.default.removeItem(at: AppGroup.deleted.appending(path: id, directoryHint: .isDirectory))
        deleted.removeAll { $0.cut.id == id }
    }

    func deleteAllForever() { for item in deleted { deleteForever(item.cut.id) } }

    /// Loads Recently deleted and drops anything there longer than 30 days.
    private func loadDeleted() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: AppGroup.deleted, includingPropertiesForKeys: nil)) ?? []
        var items: [(cut: CutSet, at: Date)] = []
        for dir in dirs {
            guard let data = try? Data(contentsOf: dir.appending(path: "cut.json")),
                  let cut = try? JSONDecoder().decode(CutSet.self, from: data) else { continue }
            let at = (try? String(contentsOf: dir.appending(path: ".deleted-at"), encoding: .utf8))
                .flatMap { ISO8601DateFormatter().date(from: $0) } ?? .now
            if Date.now.timeIntervalSince(at) > Self.keepDeletedFor { try? fm.removeItem(at: dir) } else { items.append((cut, at)) }
        }
        deleted = items.sorted { $0.at > $1.at }
    }

    // MARK: Inbox and tours

    /// Picks up what the share extension left, and any finished screen tours. Opens the newest.
    func collect() {
        var newest: String?
        let fm = FileManager.default
        let items = ((try? fm.contentsOfDirectory(at: AppGroup.inbox, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "json" }
        for file in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            defer { try? fm.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file), let item = try? JSONDecoder().decode(InboxItem.self, from: data) else { continue }
            if let video = item.video {
                newest = addVideo(at: AppGroup.inbox.appending(path: video), title: item.title, move: true)
            } else if let link = item.link.flatMap(URL.init(string:)) {
                newest = addLink(link, title: nil, runID: item.runID)
            }
        }

        let active = AppGroup.defaults.string(forKey: SharedKey.activeTour)
        let tours = (try? fm.contentsOfDirectory(at: AppGroup.tours, includingPropertiesForKeys: nil)) ?? []
        for tour in tours where tour.lastPathComponent != active {
            let framesJSON = tour.appending(path: "frames.json")
            guard let data = try? Data(contentsOf: framesJSON), let frames = try? JSONDecoder().decode([Frame].self, from: data), !frames.isEmpty else {
                try? fm.removeItem(at: tour)
                continue
            }
            let id = Self.newID()
            try? fm.createDirectory(at: folder(id), withIntermediateDirectories: true)
            try? fm.moveItem(at: tour.appending(path: "frames"), to: folder(id).appending(path: "frames"))
            try? fm.removeItem(at: tour)
            let started = Double(tour.lastPathComponent).map { Date(timeIntervalSince1970: $0) } ?? .now
            let interval = AppGroup.defaults.double(forKey: SharedKey.tourInterval)
            let cut = CutSet(id: id, title: "Screen tour", byline: Self.dayStamp(started), source: .tour, created: started,
                             duration: frames.last?.time, mode: interval > 0 ? .every(interval) : .scene, frames: frames, state: .ready)
            cuts.insert(cut, at: 0)
            cuts.sort { $0.created > $1.created }
            save(cut)
            describe(id)
            newest = id
        }
        if let newest { path = [newest] }
    }

    static func dayStamp(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
