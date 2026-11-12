import Foundation

/// One still pulled out of a video or a screen tour.
struct Frame: Codable, Identifiable, Hashable {
    var id: Int
    /// Seconds from the start of the video or tour.
    var time: Double
    /// File name inside the cut's frames folder.
    var file: String
    var kept = true
}

/// How frames are chosen.
enum Mode: Codable, Hashable {
    case every(Double)
    case scene

    var label: String {
        switch self {
        case .every(let s): "Every \(Mode.seconds(s))"
        case .scene: "Scene change"
        }
    }

    static func seconds(_ s: Double) -> String { String(format: "%gs", s) }
}

/// A cut: one video (or tour) and the frames taken from it.
struct CutSet: Codable, Identifiable, Hashable {
    enum Source: String, Codable { case video, link, tour }
    enum State: Codable, Hashable { case fetching, cutting, ready, failed(String) }

    var id: String
    var title: String
    /// Creator handle, or where it came from.
    var byline: String?
    var source: Source
    var link: String?
    var created: Date
    var duration: Double?
    var mode: Mode
    var frames: [Frame] = []
    /// The source video's file name in the cut's folder (none for tours).
    var video: String?
    var state: State
    /// GitHub run started by the share extension, collected by the app.
    var runID: Int?
    /// Who posted a link and what it says, from the fetch.
    var post: Post?
    /// A tour's one-line description, written on the phone from the text on its screens.
    var summary: String?
    /// The tour has been read for a name (whether or not one came of it), so it isn't read again.
    var described: Bool?

    var kept: [Frame] { frames.filter(\.kept) }
}

/// Who posted a link and how it's doing, as the site reports it to a logged-out visitor.
struct Post: Codable, Hashable {
    var handle: String?
    var name: String?
    var caption: String?
    /// Unix seconds.
    var posted: Double?
    var views: Int?
    var likes: Int?
    var comments: Int?
}

/// What the share extension leaves in the Inbox for the app (a JSON file next to any copied video).
struct InboxItem: Codable {
    var id: String
    var title: String?
    var link: String?
    /// File name of a copied video in the Inbox.
    var video: String?
    var runID: Int?
    var added: Date
}
