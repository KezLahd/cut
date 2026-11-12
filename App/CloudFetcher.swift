import Compression
import Foundation

/// Fetches a public post's video without the Mac: the private cut-fetcher workflow runs yt-dlp (logged out,
/// no cookies, never signed in) and hands the file back as a run artifact. See server/video.yml.
struct CloudFetcher {
    var repo: String
    var token: String

    struct Result {
        var video: URL
        var title: String?
        var byline: String?
        var post: Post?
    }

    static var configured: CloudFetcher? {
        guard let token = CloudConfig.token, !token.isEmpty, CloudConfig.repo.contains("/") else { return nil }
        return CloudFetcher(repo: CloudConfig.repo, token: token)
    }

    /// Checks the token can see the workflow, without running anything.
    func check() async throws {
        _ = try await api("GET", "actions/workflows/\(CloudConfig.workflow)")
    }

    /// Starts a run (unless the share extension already did), waits, and saves the video into `folder`.
    func fetch(_ link: URL, runID existing: Int?, name: String, into folder: URL) async throws -> Result {
        var lastError: Error = CutError("The cloud fetch didn't run.")
        for attempt in 0..<3 {
            do {
                let runID: Int
                if attempt == 0, let existing { runID = existing } else {
                    do {
                        runID = try await CloudDispatch.start(repo: repo, token: token, link: link.absoluteString, runName: "\(name)-\(attempt)")
                    } catch CloudDispatch.Failure.refused(let code) {
                        throw Self.apiError(code, repo: repo)
                    }
                }
                try await wait(for: runID)
                return try await collect(runID, into: folder)
            } catch let error as Retry {
                lastError = CutError(error.message)
            } catch let error as URLError {
                lastError = CutError("The connection dropped (\(error.code.rawValue)).")
            }
        }
        throw lastError
    }

    private struct Retry: Error { var message: String }

    private func wait(for runID: Int) async throws {
        let deadline = Date.now.addingTimeInterval(300)
        var pause = 8.0
        while Date.now < deadline {
            try await Task.sleep(for: .seconds(pause))
            pause = 3
            guard let run = try? await api("GET", "actions/runs/\(runID)") else { continue }  // a dropped poll isn't a failed run
            if run["status"] as? String == "completed" { return }
        }
        throw CutError("The cloud fetch took too long.")
    }

    private func collect(_ runID: Int, into folder: URL) async throws -> Result {
        defer { Task { [self] in await deleteRun(runID) } }
        let list = try await api("GET", "actions/runs/\(runID)/artifacts")
        guard let artifact = (list["artifacts"] as? [[String: Any]])?.first(where: { $0["name"] as? String == "out" }),
              let id = artifact["id"] as? Int else { throw Retry(message: "The cloud fetch returned nothing.") }
        let files = try Zip.entries(in: try await download("actions/artifacts/\(id)/zip"))
        guard let (name, data) = files.first(where: { $0.key.hasPrefix("source.") && !$0.key.hasSuffix(".json") }) else {
            let stderr = files["error.txt"].map { String(decoding: $0, as: UTF8.self) } ?? ""
            let s = stderr.lowercased()
            if s.contains("429") || s.contains("too many requests") { throw Retry(message: "The site turned the fetch away. Try again in a minute.") }
            if s.contains("login") || s.contains("private") || s.contains("cookies") {
                throw CutError("This post isn't public, so it can't be fetched without signing in. Share the video file instead.")
            }
            throw CutError(stderr.split(separator: "\n").last.map(String.init) ?? "The cloud fetch failed.")
        }
        let video = folder.appending(path: name)
        try data.write(to: video)
        var title: String?, post: Post?
        if let info = files["source.info.json"].flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) {
            post = Self.post(from: info)
            let desc = post?.caption?.split(separator: "\n").first.map(String.init)
            title = [desc, info["title"] as? String].compactMap { $0 }.first { !$0.isEmpty && !$0.hasPrefix("Video by") && !$0.hasPrefix("Post by") }
            if let t = title, t.count > 80 { title = String(t.prefix(78)) + "…" }
        }
        return Result(video: video, title: title, byline: post?.handle, post: post)
    }

    /// yt-dlp names the same things differently per site: on Instagram `channel` is the username and
    /// `uploader_id` a number; on TikTok `uploader` is the handle and `channel` the display name.
    static func post(from info: [String: Any]) -> Post {
        func str(_ k: String) -> String? { (info[k] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } }
        func int(_ k: String) -> Int? { (info[k] as? Int) ?? (info[k] as? Double).map(Int.init) }
        let site = (str("extractor_key") ?? "").lowercased()
        let handles: [String?], names: [String?]
        switch site {
        case let s where s.hasPrefix("instagram"): handles = [str("channel"), str("uploader_id")]; names = [str("uploader")]
        case let s where s.hasPrefix("tiktok"): handles = [str("uploader"), str("uploader_id")]; names = [str("channel"), str("creator")]
        case let s where s.hasPrefix("youtube"): handles = [str("uploader_id")]; names = [str("channel"), str("uploader")]
        default: handles = [str("uploader_id"), str("channel"), str("uploader")]; names = [str("uploader"), str("channel"), str("creator")]
        }
        // A handle is one word that isn't just digits (those are account numbers).
        let handle = handles.compactMap { $0 }.map { $0.hasPrefix("@") ? String($0.dropFirst()) : $0 }
            .first { !$0.contains(" ") && !$0.allSatisfy(\.isNumber) }
        let name = names.compactMap { $0 }.first { $0.lowercased() != handle?.lowercased() }
        let posted = (info["timestamp"] as? Double) ?? (info["timestamp"] as? Int).map(Double.init)
            ?? str("upload_date").flatMap { d -> Double? in
                let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; f.timeZone = .gmt
                return f.date(from: d)?.timeIntervalSince1970
            }
        return Post(handle: handle.map { "@\($0)" }, name: name, caption: str("description"), posted: posted,
                    views: int("view_count"), likes: int("like_count"), comments: int("comment_count"))
    }

    private func deleteRun(_ runID: Int) async {
        for _ in 0..<6 {
            if (try? await api("DELETE", "actions/runs/\(runID)")) != nil { return }
            try? await Task.sleep(for: .seconds(10))
        }
    }

    static func apiError(_ code: Int, repo: String) -> Error {
        switch code {
        case 401: CutError("GitHub refused the token. Paste a new one in Settings.")
        case 403, 404: CutError("GitHub can't see \(repo) with this token (HTTP \(code)).")
        default: Retry(message: "GitHub answered HTTP \(code).")
        }
    }

    private func request(_ method: String, _ path: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/\(path)")!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.timeoutInterval = 30
        req.cachePolicy = .reloadIgnoringLocalCacheData
        return req
    }

    @discardableResult
    private func api(_ method: String, _ path: String) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request(method, path))
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Self.apiError(code, repo: repo) }
        return data.isEmpty ? [:] : ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
    }

    /// Artifact downloads redirect to blob storage, which must not see the GitHub token.
    private func download(_ path: String) async throws -> Data {
        let (_, response) = try await URLSession.shared.data(for: request("GET", path), delegate: NoRedirect())
        guard let http = response as? HTTPURLResponse, let location = http.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location) else { throw Retry(message: "The video wasn't ready.") }
        let (data, blob) = try await URLSession.shared.data(from: url)
        guard (blob as? HTTPURLResponse)?.statusCode == 200 else { throw Retry(message: "The video download failed.") }
        return data
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}

/// Just enough ZIP to read a GitHub artifact: stored or deflated entries (same reader as Jot's).
enum Zip {
    static func entries(in data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        guard bytes.count >= 22,
              let eocd = stride(from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1).first(where: { u32($0) == 0x06054b50 })
        else { throw CutError("The cloud fetch returned a broken archive.") }
        var out: [String: Data] = [:]
        var p = u32(eocd + 16)
        for _ in 0..<u16(eocd + 10) {
            guard p + 46 <= bytes.count, u32(p) == 0x02014b50 else { break }
            let method = u16(p + 10), compressed = u32(p + 20), size = u32(p + 24)
            let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32), local = u32(p + 42)
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            p += 46 + nameLen + extraLen + commentLen
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + compressed <= bytes.count else { continue }
            switch method {
            case 0: out[name] = data.subdata(in: start..<(start + compressed))
            case 8:
                if size == 0 { out[name] = Data(); continue }
                let raw = Array(bytes[start..<(start + compressed)])
                var buffer = [UInt8](repeating: 0, count: size)
                let n = compression_decode_buffer(&buffer, size, raw, raw.count, nil, COMPRESSION_ZLIB)
                if n == size { out[name] = Data(buffer) }
            default: continue
            }
        }
        return out
    }
}
