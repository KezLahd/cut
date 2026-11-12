import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct CutWidgets: WidgetBundle {
    var body: some Widget {
        TourLiveActivity()
    }
}

/// The screen tour in the Dynamic Island and on the Lock Screen: a countdown to the first frame, then a running count of
/// frames, with Stop.
struct TourLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TourAttributes.self) { context in
            LockScreenTour(state: context.state)
                .activityBackgroundTint(.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    lead(s, size: 26).padding(.leading, 8).padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Flash(size: 26).opacity(s.flash ? 1 : 0.18).padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Tally(frames: s.frames, size: 26).padding(.trailing, 8).padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(title(s)).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        if s.phase == .recording || s.phase == .countdown { StopButton() }
                    }
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                lead(s, size: 15)
            } compactTrailing: {
                Tally(frames: s.frames, size: 15).opacity(s.phase == .countdown || s.phase == .waiting ? 0.45 : 1)
            } minimal: {
                // While the screen records, iOS's own record dot shares the Island, so ours shrinks to this one
                // bubble: a ring counting down (to the start, then to each next frame), the tally inside, and a
                // white flash over it as each frame is taken.
                Bubble(state: s)
            }
            .keylineTint(Brand.red)
        }
    }

    /// On the left: the countdown to the first frame, then a flash as each frame is taken and the time until the
    /// next. Taking frames on change has no next, so it shows the clock since the start.
    @ViewBuilder
    private func lead(_ s: TourAttributes.ContentState, size: CGFloat) -> some View {
        if s.flash {
            Flash(size: size)
        } else {
            switch s.phase {
            case .countdown:
                if let begins = s.begins, begins > .now {
                    Clock(range: (s.since ?? begins.addingTimeInterval(-60))...begins, down: true, size: size, tint: Brand.red)
                } else {
                    Mark(color: Brand.red).frame(width: size * 1.4)
                }
            case .recording:
                if let next = s.next, let begins = s.begins, next > .now {
                    Clock(range: min(begins, next)...next, down: true, size: size, tint: .white)
                } else if let begins = s.begins {
                    Clock(range: begins...Date.distantFuture, down: false, size: size, tint: .white.opacity(0.75))
                } else {
                    Mark(color: Brand.red).frame(width: size * 1.4)
                }
            case .waiting, .saved:
                Mark(color: Brand.red).frame(width: size * 1.4)
            }
        }
    }

    private func title(_ s: TourAttributes.ContentState) -> String {
        switch s.phase {
        case .waiting: "Tap Start Broadcast"
        case .countdown: "Leave Cut now · frames start at zero"
        case .recording: "Screen tour · \(s.frames) frames"
        case .saved: "Saved \(s.frames) frames"
        }
    }

}

/// A system timer that can't be squeezed into "0:…": it's given room for "0:00" in fixed-width digits.
private struct Clock: View {
    var range: ClosedRange<Date>
    var down: Bool
    var size: CGFloat
    var tint: Color

    var body: some View {
        Text(timerInterval: range, countsDown: down, showsHours: false)
            .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(tint)
            .multilineTextAlignment(.leading)
            .lineLimit(1)
            .frame(width: size * 2.8, alignment: .leading)
    }
}

/// The flash shown for a moment as each frame is taken: a white burst.
private struct Flash: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: size * 0.95, weight: .black))
            .foregroundStyle(.white)
            .shadow(color: .white.opacity(0.9), radius: size * 0.4)
            .frame(width: size * 2.8)
    }
}

/// Everything in one small circle: countdown ring, tally, flash.
private struct Bubble: View {
    var state: TourAttributes.ContentState

    var body: some View {
        ZStack {
            if state.flash {
                Circle().fill(.white)
                Image(systemName: "bolt.fill").font(.system(size: 12, weight: .black)).foregroundStyle(.black)
            } else {
                ring
                if state.phase == .countdown {
                    Mark(color: Brand.red).frame(width: 12)
                } else {
                    Text("\(state.frames)")
                        .font(.system(size: state.frames > 99 ? 8.5 : 11, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(Brand.red)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText(value: Double(state.frames)))
                }
            }
        }
        .frame(width: 26, height: 26)
    }

    /// Drains to the start during the countdown, then to each next frame. Taking frames on change has no next,
    /// so the ring stays full.
    @ViewBuilder private var ring: some View {
        let (from, to): (Date?, Date?) = state.phase == .countdown
            ? (state.since, state.begins)
            : (state.next.map { $0.addingTimeInterval(-max(0.5, state.gap)) }, state.next)
        if let from, let to, to > from {
            ProgressView(timerInterval: from...to, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.circular)
                .tint(state.phase == .countdown ? Brand.red : .white)
        } else {
            Circle().strokeBorder(Brand.red.opacity(0.6), lineWidth: 2)
        }
    }
}

/// The running count of frames, rolling up as each one lands.
private struct Tally: View {
    var frames: Int
    var size: CGFloat

    var body: some View {
        Text("\(frames)")
            .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(Brand.red)
            .contentTransition(.numericText(value: Double(frames)))
            .lineLimit(1)
    }
}

private struct StopButton: View {
    var body: some View {
        Button(intent: StopTourIntent()) {
            Image(systemName: "stop.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .frame(width: 38, height: 38).background(Brand.red, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop screen tour")
    }
}

private struct LockScreenTour: View {
    var state: TourAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Mark(color: Brand.red).frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                switch state.phase {
                case .waiting: Text("Screen tour").font(.headline); Text("Tap Start Broadcast").font(.subheadline).foregroundStyle(.secondary)
                case .countdown:
                    Text("Leave Cut now").font(.headline)
                    if let begins = state.begins, begins > .now {
                        Text(timerInterval: Date.now...begins, countsDown: true).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                case .recording:
                    Text("\(state.frames) frames").font(.headline.monospacedDigit())
                    if let begins = state.begins {
                        Text(timerInterval: begins...Date.distantFuture, countsDown: false).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                case .saved: Text("Saved \(state.frames) frames").font(.headline); Text("Open Cut to pick them").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.white)
            Spacer()
            if state.phase == .recording || state.phase == .countdown { StopButton() }
        }
        .padding(16)
    }
}
