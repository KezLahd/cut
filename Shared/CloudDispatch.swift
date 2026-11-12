import Foundation

/// Starts the cut-fetcher workflow, which downloads a public post's video with yt-dlp, logged out.
/// Small and dependency-free so the share extension can start a run straight away.
enum CloudDispatch {
    enum Failure: Error { case refused(Int), noRun, network(Error) }

    static func start(repo: String, token: String, link: String, runName: String, timeout: TimeInterval = 20) async throws -> Int {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/actions/workflows/\(CloudConfig.workflow)/dispatches")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "ref": "main", "return_run_details": true, "inputs": ["url": link, "id": runName],
        ])
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: req) } catch { throw Failure.network(error) }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Failure.refused(code) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let id = json["workflow_run_id"] as? Int else {
            throw Failure.noRun
        }
        return id
    }

    /// The first http(s) link in some shared text.
    static func firstLink(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.matches(in: text, range: range).compactMap(\.url).first { $0.scheme?.hasPrefix("http") == true }
    }
}
