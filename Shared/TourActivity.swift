import ActivityKit
import Foundation

/// The Live Activity shown in the Dynamic Island during a screen tour. The app starts it; once a tour is
/// recording, the broadcast extension moves it along with APNs pushes (Broadcast/IslandPush.swift), since iOS
/// stops a backgrounded app updating it after about 30 seconds.
struct TourAttributes: ActivityAttributes {
    typealias ContentState = TourState
}

enum TourActivity {
    static func update(_ state: TourAttributes.ContentState) async {
        for activity in Activity<TourAttributes>.activities {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    static func end(_ state: TourAttributes.ContentState?, after seconds: TimeInterval = 4) async {
        for activity in Activity<TourAttributes>.activities {
            await activity.end(state.map { ActivityContent(state: $0, staleDate: nil) },
                               dismissalPolicy: state == nil ? .immediate : .after(.now.addingTimeInterval(seconds)))
        }
    }
}
