import SwiftUI

/// Tap Link: paste a reel or video link and Cut fetches it in the cloud, logged out.
struct LinkSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var link: URL? { CloudDispatch.firstLink(in: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a link").font(.app(20, .bold)).foregroundStyle(Color.cInk)

            HStack(spacing: 8) {
                TextField("Paste a reel or video link", text: $text)
                    .font(.app(15.5))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit(add)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(Color.cSurface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                PasteButton(payloadType: String.self) { strings in
                    Task { @MainActor in text = strings.first ?? "" }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.roundedRectangle(radius: 10))
                .tint(Color.cRed)
            }

            Group {
                if text.isEmpty {
                    Text("Instagram, TikTok, YouTube and the rest. Cut only fetches what anyone can see without signing in.")
                        .foregroundStyle(Color.cMute)
                } else if let link {
                    Label { Text("\(link.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: "") ?? "Link"). Cut can fetch this.").foregroundStyle(Color.cInk) }
                        icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.cRed) }
                } else {
                    Label { Text("That isn't a link yet.").foregroundStyle(Color.cMute) }
                        icon: { Image(systemName: "questionmark.circle").foregroundStyle(Color.cMute) }
                }
            }
            .font(.app(13.5))
            .frame(minHeight: 40, alignment: .topLeading)

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle(height: 50))
                Button(action: add) {
                    Text("Cut").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(height: 50))
                .disabled(link == nil)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.cBg)
        .onAppear {
            // A link already on the clipboard goes straight in; otherwise the keyboard comes up.
            if UIPasteboard.general.hasURLs, let url = UIPasteboard.general.url { text = url.absoluteString } else { focused = true }
        }
    }

    private func add() {
        guard let link else { return }
        dismiss()
        store.path = [store.addLink(link)]
    }
}

/// Screen tour: how often to take a frame and how long to wait first, then Start. iOS then asks to Start
/// Broadcast; the wait gives time to get to the right screen or sign in.
struct TourSheet: View {
    @Environment(TourController.self) private var tour
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var tour = tour
        VStack(alignment: .leading, spacing: 0) {
            Text("Screen tour").font(.app(20, .bold)).foregroundStyle(Color.cInk)
            Text("Cut takes stills of your screen while you use other apps.")
                .font(.app(13.5)).foregroundStyle(Color.cMute).padding(.top, 4)

            VStack(alignment: .leading, spacing: 0) {
                StopSlider(label: "Take a frame every", stops: TourController.intervals,
                           name: { $0 == 0 ? "On change" : TourController.duration($0) }, value: $tour.interval)
                StopSlider(label: "Start after", stops: TourController.delays,
                           name: { $0 == 0 ? "Straight away" : TourController.duration($0) }, value: $tour.delay)
            }
            .padding(.top, 8)

            Text(note).font(.app(13)).foregroundStyle(Color.cMute).padding(.top, 10)
                .frame(minHeight: 36, alignment: .topLeading)

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle(height: 50))
                Button {
                    dismiss()
                    // The Start Broadcast sheet can't open while this one is still on screen.
                    Task { try? await Task.sleep(for: .seconds(0.45)); tour.start() }
                } label: {
                    Label("Start", systemImage: "record.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(height: 50))
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.cBg)
    }

    private var note: String {
        let every = tour.interval == 0 ? "a still each time the screen settles on something new"
            : "a still every \(TourController.duration(tour.interval))"
        let wait = tour.delay == 0 ? "Cut starts straight away" : "Cut waits \(TourController.duration(tour.delay))"
        return "After Start Broadcast, \(wait), then takes \(every). Stop from the Dynamic Island or here."
    }
}

/// Recently deleted: restore a cut, or delete it for good. Anything older than 30 days goes by itself.
struct DeletedView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmAll = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text("Cuts stay here for 30 days, then they're removed.")
                        .font(.app(13.5)).foregroundStyle(Color.cMute).padding(.bottom, 6)
                    if store.deleted.isEmpty {
                        Text("Nothing here.").font(.app(16, .medium)).foregroundStyle(Color.cMute).padding(.top, 30)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(store.deleted, id: \.cut.id) { item in
                        HStack(alignment: .center, spacing: 12) {
                            if let f = item.cut.kept.first ?? item.cut.frames.first {
                                FrameImage(url: store.deletedURL(f, in: item.cut), side: 120)
                                    .frame(width: 38, height: 64).background(Color.cSurface2)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.cut.source == .tour ? "Screen tour · \(item.cut.byline ?? "")" : item.cut.title)
                                    .font(.app(15.5, .semibold)).foregroundStyle(Color.cInk).lineLimit(2)
                                Text(daysLeft(item.at)).font(.mono(11)).foregroundStyle(Color.cMute)
                            }
                            Spacer(minLength: 6)
                            Button("Restore") { withAnimation(.snappy) { store.restore(item.cut.id) } }
                                .buttonStyle(SecondaryButtonStyle(height: 34))
                            Button { withAnimation(.snappy) { store.deleteForever(item.cut.id) } } label: {
                                Image(systemName: "trash").foregroundStyle(Color.cRed)
                            }
                            .buttonStyle(SecondaryButtonStyle(height: 34))
                            .accessibilityLabel("Delete now")
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) { Hairline() }
                    }
                }
                .padding(.horizontal, 20)
            }
            .background(Color.cBg)
            .navigationTitle("Recently deleted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if !store.deleted.isEmpty {
                    ToolbarItem(placement: .cancellationAction) { Button("Empty", role: .destructive) { confirmAll = true } }
                }
            }
            .confirmationDialog("Delete \(store.deleted.count == 1 ? "1 cut" : "\(store.deleted.count) cuts") for good?",
                                isPresented: $confirmAll, titleVisibility: .visible) {
                Button("Delete for good", role: .destructive) { store.deleteAllForever() }
            } message: { Text("This can't be undone.") }
        }
    }

    private func daysLeft(_ at: Date) -> String {
        let left = max(0, Int(ceil((Store.keepDeletedFor - Date.now.timeIntervalSince(at)) / 86_400)))
        return left == 1 ? "1 day left" : "\(left) days left"
    }
}
