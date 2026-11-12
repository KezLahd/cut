import SwiftUI

/// Covers Cut while a screen tour counts down to its first frame: a big countdown and a plain instruction to
/// leave, so it's clear the tour has started and is waiting for you to go to the app you want to capture.
/// Gone the moment frames start (or if the tour is stopped).
struct TourCountdown: View {
    @Environment(TourController.self) private var tour

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            if tour.recording, let begins = tour.begins, begins > context.date {
                screen(begins: begins, now: context.date)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: tour.recording)
    }

    private func screen(begins: Date, now: Date) -> some View {
        let left = Int(begins.timeIntervalSince(now).rounded(.up))
        return VStack(spacing: 0) {
            Spacer()
            Mark(color: .cRed).frame(width: 34)
            Text("\(left)")
                .font(.mono(120, .bold))
                .foregroundStyle(Color.cRed)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy(duration: 0.3), value: left)
                .padding(.top, 18)
            Text("Leave Cut now")
                .font(.app(26, .bold))
                .foregroundStyle(Color.cInk)
                .padding(.top, 6)
            Text("Swipe up and open the app you want to capture. The first frame is taken when this reaches zero, then the Island keeps count.")
                .font(.app(15))
                .foregroundStyle(Color.cMute)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 10)
            Spacer()
            Button { tour.stop() } label: {
                Label("Stop tour", systemImage: "stop.fill")
            }
            .buttonStyle(SecondaryButtonStyle(height: 48))
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cBg.ignoresSafeArea())
    }
}
