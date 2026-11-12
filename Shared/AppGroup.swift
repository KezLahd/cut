import Foundation

/// The App Group container the app and its three extensions share.
enum AppGroup {
    static let id = "group.com.kezlahd.cut"

    static var container: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) ?? FileManager.default.temporaryDirectory
    }

    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }

    /// One folder per cut: cut.json, source video, frames/NNN.jpg.
    static var cuts: URL { folder("Cuts") }
    /// Things the share extension drops off for the app.
    static var inbox: URL { folder("Inbox") }
    /// Screen tours the broadcast extension is writing or has finished.
    static var tours: URL { folder("Tours") }
    /// Deleted cuts, kept 30 days so they can be restored.
    static var deleted: URL { folder("Deleted") }

    private static func folder(_ name: String) -> URL {
        let url = container.appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Keys in the shared defaults.
enum SharedKey {
    /// Seconds between screen-tour frames; 0 means "when the screen changes".
    static let tourInterval = "tourInterval"
    /// The id of the tour the broadcast extension is recording, if any.
    static let activeTour = "activeTour"
    /// Frames saved so far in the active tour.
    static let tourCount = "tourCount"
    static let stopRequested = "stopRequested"
    /// Seconds between Start Broadcast and the first frame, so there's time to get to the right screen.
    static let tourDelay = "tourDelay"
    /// When the active tour starts taking frames (seconds since 1970), set by the broadcast extension.
    static let tourBegins = "tourBegins"
    /// The Live Activity's APNs push token (hex), so the broadcast extension can update the Island itself.
    static let tourPushToken = "tourPushToken"
    /// Which APNs host took the last push: sandbox for builds installed from the Mac, production for TestFlight.
    static let tourPushHost = "tourPushHost"
}
