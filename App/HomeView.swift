import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Every cut, newest first by day, under a masthead that folds its search and filters away as you scroll, like Jot's. The three ways in float in a glass dock at
/// the bottom: Photos, Screen tour, and Link.
struct HomeView: View {
    @Environment(Store.self) private var store
    @Environment(TourController.self) private var tour
    @State private var photo: PhotosPickerItem?
    @State private var settings = false
    @State private var adding = false
    @State private var touring = false
    @State private var pull: CGFloat = 0
    @State private var refreshStart: Date?
    @State private var doneAfter: TimeInterval?
    @State private var released = PullBrackets.rest
    @State private var taps = 0
    /// Where the list's visible top edge sits on screen; only changes with layout.
    @State private var listTop: CGFloat = 0
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var swiped: String?
    #if DEBUG
    @State private var sharePreview = false
    #endif
    @State private var showDeleted = false
    @FocusState private var searching: Bool
    @State private var sort: Sort = .newest
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var confirmDelete = false
    @State private var offset: CGFloat = 0
    @State private var toolsHeight: CGFloat = 92
    @State private var insetTop: CGFloat = 0
    @State private var scroll = ScrollPosition()

    private let barHeight: CGFloat = 52
    /// How far the masthead has folded, 0 open to 1 folded.
    private var travel: CGFloat { min(max(0, offset), toolsHeight) }
    private var progress: CGFloat { toolsHeight > 0 ? travel / toolsHeight : 0 }
    private var mastheadHeight: CGFloat { barHeight + (store.cuts.isEmpty ? 0 : toolsHeight) }

    enum Sort: String, CaseIterable, Identifiable {
        case newest = "Newest", oldest = "Oldest", mostFrames = "Most frames", longest = "Longest"
        var id: String { rawValue }
        var byDay: Bool { self == .newest || self == .oldest }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", tours = "Tours", links = "Links", videos = "Videos"
        var id: String { rawValue }
        func matches(_ cut: CutSet) -> Bool {
            switch self {
            case .all: true
            case .tours: cut.source == .tour
            case .links: cut.source == .link
            case .videos: cut.source == .video
            }
        }
    }

    /// The cuts the search and filter leave.
    private var shown: [CutSet] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let found = store.cuts.filter { cut in
            filter.matches(cut) && (q.isEmpty || [cut.title, cut.byline ?? "", cut.sourceName].contains { $0.lowercased().contains(q) })
        }
        switch sort {
        case .newest: return found
        case .oldest: return found.reversed()
        case .mostFrames: return found.sorted { $0.kept.count > $1.kept.count }
        case .longest: return found.sorted { ($0.duration ?? 0) > ($1.duration ?? 0) }
        }
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.path) {
            list
            .overlay(alignment: .top) { masthead }
            .overlay { if shown.isEmpty && !tour.recording { empty.padding(.top, mastheadHeight) } }
            .background(Color.cBg)
            .safeAreaInset(edge: .bottom) { if !searching { dock } }
            .navigationDestination(for: String.self) { CutView(id: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }
        .background(BroadcastPicker(controller: tour).frame(width: 1, height: 1).allowsHitTesting(false))
        .overlay { TourCountdown() }
        .sheet(isPresented: $settings) { SettingsView() }
        .sheet(isPresented: $showDeleted) { DeletedView() }
        .confirmationDialog("Delete \(selected.count == 1 ? "1 cut" : "\(selected.count) cuts")?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                withAnimation(.snappy(duration: 0.3)) { for id in selected { store.delete(id) } }
                selected = []
                selecting = false
            }
        } message: { Text("They go to Recently deleted for 30 days.") }
        .sheet(isPresented: $adding) {
            LinkSheet().presentationDetents([.height(272)]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $touring) {
            TourSheet().presentationDetents([.height(430)]).presentationDragIndicator(.visible)
        }
        #if DEBUG
        .sheet(isPresented: $sharePreview) { SharePreview() }
        #endif
        .alert("Cut", isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.alert ?? "") }
        #if DEBUG
        .onAppear {
            switch ProcessInfo.processInfo.environment["CUT_SHEET"] {
            case "link": adding = true
            case "tour": touring = true
            case "settings": settings = true
            case "share": sharePreview = true
            default: break
            }

        }
        #endif
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task {
                do {
                    guard let movie = try await item.loadTransferable(type: Movie.self) else { throw CutError("No video") }
                    store.path = [store.addVideo(at: movie.url, title: nil, move: true)]
                } catch {
                    store.alert = "Couldn't load that video from Photos."
                }
            }
        }
    }

    // MARK: Header

    /// The bar stays; the search and filters below it slide up under it as the list scrolls.
    private var masthead: some View {
        VStack(spacing: 0) {
            bar.frame(height: barHeight).background(Color.cBg).zIndex(1)
            if !store.cuts.isEmpty {
                tools
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { toolsHeight = $0 }
                    .offset(y: -travel)
                    .opacity(1 - min(1, progress * 1.6))
            }
        }
        .frame(height: mastheadHeight - travel, alignment: .top)
        .clipped()
        .background(Color.cBg.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Hairline().opacity(progress) }
    }

    private var bar: some View {
        HStack(spacing: 10) {
            Wordmark(ut: .cInk).frame(height: 30 - 6 * progress).accessibilityLabel("Cut")
            Spacer()
            if selecting {
                Button(selected.count == shown.count ? "None" : "All") {
                    selected = selected.count == shown.count ? [] : Set(shown.map(\.id))
                }
                .buttonStyle(.glass)
                Button("Done") { withAnimation(.snappy(duration: 0.25)) { selecting = false; selected = [] } }
                    .buttonStyle(.glassProminent)
                    .tint(Color.cRed)
            } else {
                Button("Select") { withAnimation(.snappy(duration: 0.25)) { selecting = true; swiped = nil } }
                    .buttonStyle(.glass)
                    .disabled(store.cuts.isEmpty)
                Button { settings = true } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.cInk)
                        .frame(width: 22, height: 22)
                }
                .accessibilityLabel("Settings")
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
        }
        .font(.app(15, .semibold))
        .foregroundStyle(Color.cInk)
        .padding(.leading, Inset.text)
        .padding(.trailing, Inset.container)
    }

    /// Search, then the filters as plain words, inline like Jot's.
    private var tools: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.cMute)
                TextField("Search cuts", text: $query)
                    .font(.app(16)).foregroundStyle(Color.cInk)
                    .focused($searching).submitLabel(.search).onSubmit { searching = false }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.cMute) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
                if searching {
                    Button("Done") { searching = false }.font(.app(15, .semibold)).buttonStyle(.plain).foregroundStyle(Color.cRed)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Color.cSurface2, in: Capsule())
            .padding(.horizontal, Inset.container)

            HStack(spacing: 18) {
                ForEach(Filter.allCases) { f in
                    Button { withAnimation(.snappy(duration: 0.2)) { filter = f } } label: {
                        Text(f.rawValue)
                            .font(.app(14.5, filter == f ? .semibold : .medium))
                            .foregroundStyle(filter == f ? Color.cInk : Color.cMute)
                            .padding(.vertical, 6)
                            .overlay(alignment: .bottom) { if filter == f { Rectangle().fill(Color.cRed).frame(height: 2) } }
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(sort.rawValue)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .font(.app(14.5, .medium))
                    .foregroundStyle(Color.cMute)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Inset.text)
        }
        .padding(.bottom, 10)
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                pullAnchor
                if tour.recording { LiveTourRow().padding(.horizontal, Inset.text) }
                if sort.byDay {
                    ForEach(days, id: \.day) { section in
                        dayLabel(section.day)
                        ForEach(section.cuts) { cut in line(cut) }
                    }
                } else {
                    ForEach(shown) { cut in line(cut) }
                }
                if !shown.isEmpty {
                    Text(shown.count == 1 ? "1 cut" : "\(shown.count) cuts")
                        .font(.app(13, .medium)).foregroundStyle(Color.cMute)
                        .frame(maxWidth: .infinity).padding(.top, 18).padding(.bottom, 24)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { listTop = $0 }
        .contentMargins(.top, mastheadHeight + (refreshStart == nil ? 0 : 62), for: .scrollContent)
        .contentMargins(.top, mastheadHeight, for: .scrollIndicators)
        .scrollBounceBehavior(.always)
        .scrollPosition($scroll)
        .scrollTargetBehavior(FoldSnap(range: store.cuts.isEmpty ? 0 : toolsHeight, insetTop: insetTop))
        .scrollEdgeEffectHidden(true, for: .top)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, v in
            offset = v
            pull = max(0, -v)
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.top } action: { _, v in insetTop = v }
        .scrollDismissesKeyboard(.immediately)
        .onScrollPhaseChange { old, new in
            if new == .interacting, swiped != nil { withAnimation(.snappy(duration: 0.25)) { swiped = nil } }
            // A slow let-go has no fling to redirect, so the fold settles here.
            if new == .idle, travel > 0.5, travel < toolsHeight - 0.5 {
                withAnimation(.snappy(duration: 0.3)) { scroll.scrollTo(y: (travel < toolsHeight / 2 ? 0 : toolsHeight) - insetTop) }
            }
            if old == .interacting, new != .interacting, pull >= PullBrackets.threshold, refreshStart == nil { refresh() }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: pull >= PullBrackets.threshold) { _, armed in armed && refreshStart == nil }
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.9), trigger: taps)
        // Past the line, ticks that come faster and firmer the further you stretch it.
        .sensoryFeedback(trigger: PullBrackets.stretchStep(for: pull)) { old, new in
            new > old && refreshStart == nil ? .impact(flexibility: .rigid, intensity: PullBrackets.stretchIntensity(new)) : nil
        }
        // Letting go: a thud like a band snapping back, harder the further it was stretched.
        .sensoryFeedback(trigger: refreshStart) { old, new in
            old == nil && new != nil ? .impact(weight: .heavy, intensity: 0.7 + 0.3 * Double(PullBrackets.stretch(for: pull))) : nil
        }
    }

    /// The brackets hang from the top of the list itself, so they move in the same frame as the rows instead of
    /// a frame behind (the pull distance reaches SwiftUI state one frame late). Where they sit within the gap is
    /// worked out in the render pass from the list's own position, so the centring never lags either.
    private var pullAnchor: some View {
        Color.clear.frame(height: 0)
            .overlay(alignment: .bottom) {
                if pull > 1 || refreshStart != nil {
                    PullBrackets(pull: pull, refreshStart: refreshStart, doneAfter: doneAfter, released: released)
                        .frame(height: Self.bracketBox)
                        .visualEffect { [top = listTop + mastheadHeight] content, proxy in
                            // The gap above the first row: from the list's visible top edge to this box's bottom.
                            // Measured on screen, where it's drawn. The scroll view's own spaces shift by the
                            // 62 pt refresh margin the moment it's added, which made the brackets jump on release.
                            let gap = max(0, proxy.frame(in: .global).maxY - top)
                            return content.offset(y: (Self.bracketBox - gap) / 2)
                        }
                }
            }
    }

    private static let bracketBox: CGFloat = 200

    /// Brings in anything shared or recorded since. The film rolls until that's done (at least a second),
    /// then stops, is cut, and the brackets shut.
    private func refresh() {
        released = PullBrackets.spread(for: pull)
        doneAfter = nil
        refreshStart = .now
        let started = Date.now
        Task {
            store.collect()
            tour.refresh()
            let elapsed = Date.now.timeIntervalSince(started)
            if elapsed < PullBrackets.minimumLoad { try? await Task.sleep(for: .seconds(PullBrackets.minimumLoad - elapsed)) }
            let done = Date.now.timeIntervalSince(started)
            doneAfter = done
            try? await Task.sleep(for: .seconds(PullBrackets.sliceAfter))
            taps += 1
            try? await Task.sleep(for: .seconds(PullBrackets.snapAfter - PullBrackets.sliceAfter))
            taps += 1
            try? await Task.sleep(for: .seconds(PullBrackets.endAfter - PullBrackets.snapAfter))
            // Added without animation, so the scroll view's own bounce carries the list down to it (animating
            // the margin moved the layout ahead of what was drawn, and the brackets jumped a frame). Taken away
            // animated: by then the brackets have gone.
            withAnimation(.snappy(duration: 0.35)) { refreshStart = nil }
        }
    }


    private var days: [(day: String, cuts: [CutSet])] {
        var out: [(day: String, cuts: [CutSet])] = []
        for cut in shown {
            let day = cut.created.dayLabel
            if out.last?.day == day { out[out.count - 1].cuts.append(cut) } else { out.append((day, [cut])) }
        }
        return out
    }

    private func dayLabel(_ day: String) -> some View {
        Text(day.uppercased())
            .font(.mono(10.5, .medium)).tracking(0.8)
            .foregroundStyle(Color.cMute)
            .padding(EdgeInsets(top: 22, leading: Inset.text, bottom: 2, trailing: Inset.text))
    }

    /// The mark, then what's missing: nothing at all yet, or nothing that fits the search and filter.
    private var empty: some View {
        let filtered = !store.cuts.isEmpty
        return VStack(spacing: 10) {
            Mark(color: .cRed).frame(width: 52)
            Text(filtered ? "No matches" : "Nothing cut yet").font(.app(18, .semibold)).foregroundStyle(Color.cInk)
            Text(filtered ? "Nothing you've cut fits that." : "Tap Link and paste a reel, pick a video from Photos, or record a screen tour.")
                .font(.app(14)).foregroundStyle(Color.cMute).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    /// One cut on a hairline. Selecting turns it into a tick box; otherwise it opens, and swipes to delete.
    @ViewBuilder
    private func line(_ cut: CutSet) -> some View {
        if selecting {
            let on = selected.contains(cut.id)
            Button {
                if on { selected.remove(cut.id) } else { selected.insert(cut.id) }
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(on ? Color.cRed : Color.cMute.opacity(0.6))
                        .contentTransition(.symbolEffect(.replace))
                    CutRow(cut: cut)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: on)
            .padding(.horizontal, Inset.text)
        } else {
            NavigationLink(value: cut.id) { CutRow(cut: cut) }
                .buttonStyle(RowStyle())
                .padding(.horizontal, Inset.text)
                .background(Color.cBg)
                .modifier(SwipeToDelete(id: cut.id, open: $swiped, enabled: true, title: "Delete") {
                    withAnimation(.snappy(duration: 0.3)) { store.delete(cut.id) }
                })
                .contextMenu {
                    Button("Select", systemImage: "checkmark.circle") {
                        withAnimation(.snappy(duration: 0.25)) { selecting = true; selected = [cut.id] }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { store.delete(cut.id) }
                }
        }
    }

    // MARK: Dock

    /// Photos and Screen tour as glass circles, Link in red. While a tour runs, its circle becomes Stop.
    private var dock: some View {
        HStack(spacing: 10) {
            Spacer()
            if selecting {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label(selected.isEmpty ? "Delete" : "Delete \(selected.count)", systemImage: "trash")
                        .font(.app(16.5, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).frame(height: 34)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.cRed)
                .disabled(selected.isEmpty)
                .transition(.scale.combined(with: .opacity))
            } else {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $photo, matching: .videos, preferredItemEncoding: .current) {
                        Image(systemName: "film").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.cInk)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Pick a video from Photos")

                    if tour.recording {
                        Button { tour.stop() } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "stop.fill").font(.system(size: 13, weight: .bold))
                                Text("Stop · \(tour.frames)").font(.app(16.5, .bold)).monospacedDigit()
                            }
                            .foregroundStyle(.white).padding(.horizontal, 8).frame(height: 34)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Color.cRed)
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Button { touring = true } label: {
                            Image(systemName: "record.circle").font(.system(size: 19, weight: .semibold)).foregroundStyle(Color.cInk)
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Screen tour")
                    }

                    Button { adding = true } label: {
                        Label("Link", systemImage: "link")
                            .font(.app(16.5, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).frame(height: 34)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.cRed)
                }
            }
            .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: selecting)
        .animation(.snappy(duration: 0.25), value: tour.recording)
        .padding(.horizontal, Inset.container)
        .padding(.bottom, 6)
    }
}

/// Recording now: a breathing red dot, the count and the clock, at the top of the list.
private struct LiveTourRow: View {
    @Environment(TourController.self) private var tour
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.cRed).frame(width: 9, height: 9).opacity(pulse ? 0.3 : 1)
                .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
            Text("Screen tour").font(.app(16.5, .semibold)).foregroundStyle(Color.cInk)
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { t in
                Text(status(at: t.date)).font(.mono(12)).foregroundStyle(Color.cRed)
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func status(at now: Date) -> String {
        guard let begins = tour.begins else { return "Starting…" }
        if now < begins { return "starts in \(Int(begins.timeIntervalSince(now).rounded(.up)))s" }
        return "\(tour.frames) · \(timecode(now.timeIntervalSince(begins)))"
    }
}

/// Where it's from and how long in red, the title, then the kept frames as a strip of film at their own shape,
/// running off the edge when there are more than fit.
/// Where a cut came from as a small glyph, like Jot's: Instagram's camera, a play button, the record dot.
struct SourceIcon: View {
    var cut: CutSet
    var size: CGFloat = 16
    var body: some View {
        Group {
            if cut.sourceName == "Instagram" {
                InstagramGlyph().stroke(Color.cInk, lineWidth: size * 0.1)
            } else {
                Image(systemName: symbol).font(.system(size: size * 0.82, weight: .semibold)).foregroundStyle(Color.cInk)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch cut.source {
        case .tour: "record.circle"
        case .video: "film"
        case .link:
            switch cut.sourceName {
            case "TikTok": "music.note"
            case "YouTube": "play.rectangle.fill"
            case "X": "xmark"
            default: "link"
            }
        }
    }
}

/// Rounded square, lens and flash dot, drawn to sit with SF Symbols at the same size (same as Jot's).
struct InstagramGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06)
        var p = Path(roundedRect: r, cornerRadius: r.width * 0.3, style: .continuous)
        let lens = r.width * 0.23
        p.addEllipse(in: CGRect(x: r.midX - lens, y: r.midY - lens, width: lens * 2, height: lens * 2))
        let dot = r.width * 0.035
        let c = CGPoint(x: r.maxX - r.width * 0.24, y: r.minY + r.width * 0.24)
        p.addEllipse(in: CGRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2))
        return p
    }
}

struct CutRow: View {
    @Environment(Store.self) private var store
    var cut: CutSet

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                SourceIcon(cut: cut)
                (Text(cut.rowLead).foregroundStyle(Color.cInk)
                    + Text(cut.rowTail.map { " · \($0)" } ?? "").foregroundStyle(Color.cMute))
                    .font(.app(13.5, .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(meta).font(.mono(12)).foregroundStyle(Color.cMute)
            }
            Text(title).font(.app(17.5, .semibold)).foregroundStyle(Color.cInk).lineLimit(2)
                .multilineTextAlignment(.leading).padding(.top, 8)
            if let line = secondLine {
                Text(line).font(.app(14)).foregroundStyle(Color.cMute).lineLimit(2)
                    .multilineTextAlignment(.leading).padding(.top, 3)
            } else if store.describing.contains(cut.id) {
                HStack(spacing: 7) {
                    OrbView(kind: .shaping, size: 16)
                    Text(cut.source == .tour ? "Reading the screens" : cut.post == nil ? "Getting who posted it" : "Working out what it's about").font(.app(13.5)).foregroundStyle(Color.cRed)
                }
                .padding(.top, 5)
            }
            strip.padding(.top, 12)
        }
        .padding(.vertical, 16)
        .contentShape(.rect)
        .overlay(alignment: .bottom) { Hairline() }
    }

    /// An unnamed tour goes by the time it was recorded (the day is the section above); anything else by its title.
    private var title: String {
        cut.hasName ? cut.title : cut.created.formatted(date: .omitted, time: .shortened)
    }

    /// A tour's line about itself, or who posted a link.
    private var secondLine: String? {
        switch cut.source {
        case .tour: cut.summary.flatMap { $0.isEmpty ? nil : $0 }
        case .link: cut.post?.rest(after: cut.title).map { $0.replacingOccurrences(of: "\n", with: " ") }
        case .video: nil
        }
    }

    private var meta: String {
        var parts: [String] = []
        if cut.state == .ready { parts.append("\(cut.kept.count) kept") }
        if let d = cut.duration { parts.append(timecode(d)) }
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder private var strip: some View {
        switch cut.state {
        case .fetching: status("Fetching in the cloud", orb: .searching)
        case .cutting: status("Cutting · \(cut.frames.count) frames", orb: .shaping)
        case .failed: status("Couldn't finish · tap to see why")
        case .ready:
            let aspect = store.aspect(of: cut)
            let height: CGFloat = aspect < 1 ? 128 : 84
            // As many whole frames as fit the row; when there are more, a plain "+N" after them says how many are left.
            // Nothing runs off the edge, so there's no cut-off frame and no fade.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: cut.kept.isEmpty ? 16 : height)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        let w = height * aspect, gap: CGFloat = 5
                        let fit = max(1, Int((geo.size.width + gap) / (w + gap)))
                        let more = cut.kept.count > fit
                        // When there are more, leave room at the end for a plain "+N".
                        let label = 14 + 9 * CGFloat(String(cut.kept.count).count)
                        let shown = more ? max(1, Int((geo.size.width - label + gap) / (w + gap))) : cut.kept.count
                        HStack(spacing: gap) {
                            ForEach(Array(cut.kept.prefix(shown))) { f in
                                FrameImage(url: store.url(f, in: cut), side: 200)
                                    .frame(width: w, height: height)
                                    .background(Color.cSurface2)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            }
                            if more {
                                Text("+\(cut.kept.count - shown)")
                                    .font(.app(15, .semibold)).foregroundStyle(Color.cMute)
                                    .lineLimit(1).fixedSize()
                                    .padding(.leading, 4)
                                    .frame(height: height)
                            }
                            if cut.kept.isEmpty {
                                Text("All dropped").font(.mono(11)).foregroundStyle(Color.cMute)
                            }
                        }
                    }
                }
        }
    }

    private func status(_ text: String, orb: OrbView.Kind? = nil) -> some View {
        HStack(spacing: 7) {
            if let orb { OrbView(kind: orb, size: 18) } else { Circle().fill(Color.cRed).frame(width: 6, height: 6) }
            Text(text).font(.mono(11.5)).foregroundStyle(Color.cRed)
        }
    }
}

extension Date {
    /// "Today", "Yesterday", or "8 Nov".
    var dayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "Today" }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.day().month(.abbreviated))
    }
}

/// A video picked from Photos, copied somewhere Cut can keep it.
struct Movie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let dest = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "." + received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Movie(url: dest)
        }
    }
}

/// Lets the fold finish: a fling that would stop with the search half tucked lands open or folded instead.
private struct FoldSnap: ScrollTargetBehavior {
    var range: CGFloat
    var insetTop: CGFloat
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let y = target.rect.minY + insetTop
        guard range > 0, y > 0, y < range else { return }
        target.rect.origin.y = (y < range / 2 ? 0 : range) - insetTop
    }
}

#if DEBUG
/// The share screen as it plays after sharing a reel, for checking it without the share sheet.
private struct SharePreview: View {
    @State private var start = Date.now
    @State private var outcome: ShareOutcome?
    @State private var done: TimeInterval?

    var body: some View {
        ShareScreen(start: start, outcome: outcome, doneAfter: done, dismiss: {})
            .task {
                try? await Task.sleep(for: .seconds(2.2))
                outcome = .cloud(URL(string: "https://www.instagram.com/reel/demo/")!)
                done = Date.now.timeIntervalSince(start)
            }
    }
}
#endif
