import SwiftUI

/// How often to take a frame: a slider from 0.25 s to 10 s, and the video is cut again when you let go. Scene sits beside it for cutting on each change instead.
struct IntervalSlider: View {
    @Environment(Store.self) private var store
    var cut: CutSet

    static let stops: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]
    @State private var dragging: Int?

    private var scene: Bool { if case .scene = cut.mode { dragging == nil } else { false } }

    private var index: Int {
        if let dragging { return dragging }
        guard case .every(let s) = cut.mode else { return Self.stops.firstIndex(of: 2)! }
        return Self.stops.indices.min { abs(Self.stops[$0] - s) < abs(Self.stops[$1] - s) }!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(scene ? "A frame on each scene change" : "A frame every \(Mode.seconds(Self.stops[index]))")
                    .font(.app(15, .semibold)).foregroundStyle(Color.cInk)
                    .contentTransition(.numericText())
                Text(estimate).font(.app(15)).foregroundStyle(Color.cMute).lineLimit(1)
                Spacer(minLength: 8)
                Button { store.recut(cut.id, mode: .scene) } label: {
                    Text("Scene").font(.app(14, .semibold))
                        .foregroundStyle(scene ? Color.cRed : Color.cMute)
                        .padding(.vertical, 6).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(scene ? .isSelected : [])
            }
            track
        }
        .animation(.snappy(duration: 0.18), value: index)
        .sensoryFeedback(.selection, trigger: dragging) { old, new in old != nil && new != nil && old != new }
    }

    private var estimate: String {
        if scene { return cut.state == .ready ? " · \(cut.frames.count) frames" : "" }
        guard let d = cut.duration, d > 0 else { return "" }
        let n = min(Extractor.maxFrames, Int((d / Self.stops[index]).rounded(.up)))
        return " · \(n) frames"
    }

    /// Apple's own slider, stepping through the stops; the video is cut again when you let go.
    private var track: some View {
        Slider(value: Binding(get: { Double(index) }, set: { dragging = Int($0.rounded()) }),
               in: 0...Double(Self.stops.count - 1), step: 1) { editing in
            if !editing, let i = dragging {
                store.recut(cut.id, mode: .every(Self.stops[i]))
                dragging = nil
            }
        }
        .tint(scene ? Color.cMute : Color.cRed)
        .accessibilityLabel("Frame every")
        .accessibilityValue(scene ? "scene change" : Mode.seconds(Self.stops[index]))
    }
}
