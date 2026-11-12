import CryptoKit
import Foundation

/// Moves the Dynamic Island along from the broadcast extension by sending the Live Activity silent APNs update
/// pushes. The app can't do it: iOS stops a backgrounded app updating its Live Activity after about 30 seconds,
/// and Apple's supported route for background updates is push. The extension is the one taking frames anyway.
///
/// Pushes go out at most once a second, each newer than the last (APNs timestamps are whole seconds and an
/// update that isn't newer is ignored), and only the latest waiting state is sent.
final class IslandPush {
    private let queue = DispatchQueue(label: "com.kezlahd.cut.island")
    private var pending: Push?
    private var lastSecond = 0
    private var waiting = false
    private var jwt: (token: String, made: Date)?

    private struct Push {
        var state: TourState
        var end = false
        var alert: (title: String, body: String)?
    }

    func update(_ state: TourState, alert: (title: String, body: String)? = nil) {
        queue.async { self.pending = Push(state: state, alert: alert); self.pump() }
    }

    /// Ends the activity, leaving the final state up for a few seconds. Waits briefly for the push to leave, since
    /// the extension is about to be torn down.
    func end(_ state: TourState) {
        let done = DispatchSemaphore(value: 0)
        queue.async {
            self.pending = nil
            let now = max(Int(Date().timeIntervalSince1970), self.lastSecond + 1)
            self.lastSecond = now
            self.post(Push(state: state, end: true), at: now) { done.signal() }
        }
        _ = done.wait(timeout: .now() + 3)
    }

    private func pump() {
        guard !waiting, let push = pending else { return }
        let now = Int(Date().timeIntervalSince1970)
        if now > lastSecond {
            pending = nil
            lastSecond = now
            post(push, at: now) {}
        } else {
            waiting = true
            let wait = Double(lastSecond + 1) - Date().timeIntervalSince1970 + 0.02
            queue.asyncAfter(deadline: .now() + max(0.02, wait)) { self.waiting = false; self.pump() }
        }
    }

    private func post(_ push: Push, at timestamp: Int, done: @escaping () -> Void) {
        guard let device = AppGroup.defaults.string(forKey: SharedKey.tourPushToken), let auth = bearer(),
              let data = try? JSONEncoder().encode(push.state),
              let state = try? JSONSerialization.jsonObject(with: data) else { return done() }
        var aps: [String: Any] = ["timestamp": timestamp, "event": push.end ? "end" : "update", "content-state": state]
        if push.end { aps["dismissal-date"] = timestamp + 4 }
        if let alert = push.alert { aps["alert"] = ["title": alert.title, "body": alert.body] }
        guard let body = try? JSONSerialization.data(withJSONObject: ["aps": aps]) else { return done() }

        // Builds installed from the Mac talk to the sandbox, TestFlight builds to production; remember which worked.
        let known = AppGroup.defaults.string(forKey: SharedKey.tourPushHost)
        let hosts = known.map { [$0] + Self.hosts.filter { $0 != known } } ?? Self.hosts
        send(body, device: device, auth: auth, hosts: hosts, done: done)
    }

    private static let hosts = ["api.sandbox.push.apple.com", "api.push.apple.com"]

    private func send(_ body: Data, device: String, auth: String, hosts: [String], done: @escaping () -> Void) {
        guard let host = hosts.first, let url = URL(string: "https://\(host)/3/device/\(device)") else { return done() }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("bearer \(auth)", forHTTPHeaderField: "authorization")
        request.setValue("com.kezlahd.cut.push-type.liveactivity", forHTTPHeaderField: "apns-topic")
        request.setValue("liveactivity", forHTTPHeaderField: "apns-push-type")
        request.setValue("10", forHTTPHeaderField: "apns-priority")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let reason = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            AppGroup.defaults.set("\(host) \(status) \(reason)", forKey: "tourPushLast")
            if status == 200 {
                AppGroup.defaults.set(host, forKey: SharedKey.tourPushHost)
                done()
            } else if reason.contains("BadDeviceToken"), hosts.count > 1 {
                self.send(body, device: device, auth: auth, hosts: Array(hosts.dropFirst()), done: done)
            } else {
                done()
            }
        }.resume()
    }

    /// The APNs provider token: an ES256 JWT, good for an hour, remade after 40 minutes.
    private func bearer() -> String? {
        if let jwt, Date().timeIntervalSince(jwt.made) < 40 * 60 { return jwt.token }
        guard let key = try? P256.Signing.PrivateKey(pemRepresentation: APNsKey.pem) else { return nil }
        let head = Self.base64(Data(#"{"alg":"ES256","kid":"\#(APNsKey.id)"}"#.utf8))
        let claims = Self.base64(Data(#"{"iss":"\#(APNsKey.team)","iat":\#(Int(Date().timeIntervalSince1970))}"#.utf8))
        guard let signature = try? key.signature(for: Data("\(head).\(claims)".utf8)) else { return nil }
        let token = "\(head).\(claims).\(Self.base64(signature.rawRepresentation))"
        jwt = (token, Date())
        return token
    }

    private static func base64(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
