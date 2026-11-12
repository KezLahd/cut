import Foundation

/// Cross-process pings between the app, the broadcast extension and the Live Activity's Stop button.
enum DarwinCenter {
    static let stopTour = "com.kezlahd.cut.stopTour"
    static let tourChanged = "com.kezlahd.cut.tourChanged"

    static func post(_ name: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }
}

/// Calls `handler` whenever `name` is posted, until released.
final class DarwinObserver {
    private let name: String
    private let handler: () -> Void

    init(_ name: String, handler: @escaping () -> Void) {
        self.name = name
        self.handler = handler
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
                                        { _, observer, _, _, _ in
                                            guard let observer else { return }
                                            Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue().handler()
                                        },
                                        name as CFString, nil, .deliverImmediately)
    }

    deinit {
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
                                           CFNotificationName(name as CFString), nil)
    }
}
