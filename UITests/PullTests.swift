import XCTest

/// Drives the pull-to-refresh with a real touch so it can be screen-recorded and checked frame by frame:
/// press on the list, drag down slowly, hold past the line, let go, and wait for the refresh to finish.
/// Launches with the sample cuts (CUT_DEMO), so it needs no data of its own. Simulator only.
final class PullTests: XCTestCase {
    func testPullToRefresh() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CUT_DEMO"] = "1"
        app.launch()
        sleep(2)
        for _ in 0..<2 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            let end = start.withOffset(CGVector(dx: 0, dy: 260))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: 380, thenHoldForDuration: 0.4)
            sleep(4)
        }
    }
}
