import AppIntents
import Foundation

/// The Stop button in the Dynamic Island and on the Lock Screen. It runs in the app's process and asks the
/// broadcast extension to finish.
struct StopTourIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop screen tour"
    static var description = IntentDescription("Stops recording the screen tour and saves its frames.")

    func perform() async throws -> some IntentResult {
        AppGroup.defaults.set(true, forKey: SharedKey.stopRequested)
        DarwinCenter.post(DarwinCenter.stopTour)
        return .result()
    }
}
