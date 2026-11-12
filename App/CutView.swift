import ImageIO
import SwiftUI
import UIKit

/// One cut: watch it being made, then tap frames to drop them and send the rest to Claude.
struct CutView: View {
    /// Claude takes at most this many images in one message, so bigger sets go in batches.
    static let batch = 16
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var id: String

    @State private var preview: Frame?
    @State private var sharing: [URL]?
    @State private var chooseBatch = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var fullCaption = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let cut = store.cut(id) {
            let aspect = store.aspect(of: cut)
            // As many across as the width allows, like a contact sheet: four tall frames on a phone held upright,
            // more on its side; wide frames get more room each.
            let columns = [GridItem(.adaptive(minimum: aspect < 1 ? 84 : 150), spacing: 8, alignment: .top)]
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    byline(cut)
                    Text(cut.displayTitle).font(.app(21, .semibold)).foregroundStyle(Color.cInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    meta(cut).padding(.top, 8)
                    if cut.source == .tour { tourSummary(cut) } else if cut.source == .link { caption(cut) }
                    switch cut.state {
                    case .fetching:
                        Working(text: "Fetching the video in the cloud, logged out. This takes about 20 seconds.")
                    case .failed(let why):
                        Failed(text: why) { store.retry(id) }
                    case .cutting, .ready:
                        if cut.source != .tour && cut.video != nil { IntervalSlider(cut: cut).padding(.top, 22) }
                        if cut.state == .cutting { progressBar(cut).padding(.top, 14) }
                        sheetLine(cut).padding(.top, 22)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Array(cut.frames.enumerated()), id: \.element.id) { n, frame in
                                FrameCell(url: store.url(frame, in: cut), frame: frame, number: n + 1, aspect: aspect) {
                                    store.toggle(frame, in: id)
                                }
                                .onTapGesture { preview = frame }
                            }
                        }
                        .padding(.top, 12)
                        // The frames are containers: out to the container margin while the words sit at the text one.
                        .padding(.horizontal, Inset.container - Inset.text)
                    }
                }
                .padding(.horizontal, Inset.text)
                .padding(.bottom, 110)
            }
            .background(Color.cBg)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { if cut.state == .ready { dock(cut) } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Keep all", systemImage: "checkmark.circle") { store.setAll(true, in: id) }
                        Button("Drop all", systemImage: "circle.slash") { store.setAll(false, in: id) }
                        Divider()
                        Button("Rename", systemImage: "pencil") { newName = cut.displayTitle; renaming = true }
                        if cut.source != .video {
                            Button(cut.source == .tour ? "Name it from the screens" : "Name it from the video",
                                   systemImage: "text.viewfinder") { store.describe(id) }
                        }
                        if cut.source == .link {
                            Button("Refresh details", systemImage: "arrow.clockwise") { store.refreshDetails(id) }
                        }
                        if let link = cut.link.flatMap(URL.init(string:)) {
                            Button("Open on \(cut.sourceName)", systemImage: "arrow.up.right") { openURL(link) }
                        }
                        Divider()
                        Button("Delete cut", systemImage: "trash", role: .destructive) { store.delete(id) }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
            .alert("Rename", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Save") { store.rename(id, to: newName) }
                Button("Cancel", role: .cancel) {}
            }
            .fullScreenCover(item: $preview) { frame in FrameViewer(id: id, start: frame.id) }
            #if DEBUG
            .onAppear { if ProcessInfo.processInfo.environment["CUT_FRAME"] != nil { preview = cut.frames.dropFirst(2).first } }
            #endif
            .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
                ActivitySheet(items: sharing ?? []).ignoresSafeArea()
            }
            .confirmationDialog("Claude takes \(Self.batch) images per message", isPresented: $chooseBatch, titleVisibility: .visible) {
                let kept = cut.kept
                ForEach(Array(stride(from: 0, to: kept.count, by: Self.batch)), id: \.self) { start in
                    let end = min(start + Self.batch, kept.count)
                    Button("Send \(start + 1)–\(end)") { sharing = kept[start..<end].map { store.url($0, in: cut) } }
                }
            } message: {
                Text("Send them in batches of \(Self.batch), one message each.")
            }
        } else {
            Color.cBg.onAppear { dismiss() }
        }
    }

    /// The same first line as its row on home: where it came from, who posted it, what kind of post.
    private func byline(_ cut: CutSet) -> some View {
        HStack(spacing: 7) {
            SourceIcon(cut: cut)
            (Text(cut.rowLead).foregroundStyle(Color.cInk)
                + Text(cut.rowTail.map { " · \($0)" } ?? "").foregroundStyle(Color.cMute))
                .font(.app(13.5, .semibold))
                .lineLimit(1)
        }
    }

    /// How long and when, with the way back to the post on the same line.
    private func meta(_ cut: CutSet) -> some View {
        HStack(spacing: 4) {
            if store.describing.contains(cut.id) {
                OrbView(kind: cut.source == .tour ? .shaping : .searching, size: 15).padding(.trailing, 2)
            }
            Text(detail(cut)).foregroundStyle(Color.cMute).lineLimit(1)
            Spacer(minLength: 12)
            viewLink(cut)
        }
        .font(.app(14))
    }

    private func detail(_ cut: CutSet) -> String {
        let when = cut.post?.posted.map { "Posted " + Date(timeIntervalSince1970: $0).formatted(.dateTime.day().month(.abbreviated)) }
            ?? cut.created.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        return [cut.duration.map(timecode), when].compactMap { $0 }.joined(separator: " · ")
    }

    /// Back to the post, opening in its own app when it's installed.
    @ViewBuilder private func viewLink(_ cut: CutSet) -> some View {
        if let link = cut.link.flatMap(URL.init(string:)) {
            Link(destination: link) {
                HStack(spacing: 3) {
                    Text("View on \(cut.sourceName)")
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold))
                }
                .font(.app(14, .semibold))
                .foregroundStyle(Color.cRed)
                .lineLimit(1).fixedSize()
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    /// The rest of what they wrote, three lines until tapped.
    @ViewBuilder private func caption(_ cut: CutSet) -> some View {
        if let caption = cut.post?.rest(after: cut.title) {
            Text(caption).font(.app(14)).foregroundStyle(Color.cMute)
                .lineLimit(fullCaption ? nil : 3).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .contentShape(.rect)
                .onTapGesture { withAnimation(.snappy) { fullCaption.toggle() } }
        }
    }

    /// What the phone made of a tour's screens.
    @ViewBuilder private func tourSummary(_ cut: CutSet) -> some View {
        if let summary = cut.summary, !summary.isEmpty, !store.describing.contains(cut.id) {
            Text(summary).font(.app(14)).foregroundStyle(Color.cMute)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
        }
    }

    /// Labelled like home's day headings: how many of the frames are kept.
    private func sheetLine(_ cut: CutSet) -> some View {
        (Text("\(cut.kept.count) of \(cut.frames.count) kept".uppercased()).foregroundStyle(Color.cInk)
            + Text("  ·  tap one to look".uppercased()).foregroundStyle(Color.cMute))
            .font(.mono(10.5, .medium)).tracking(0.8)
            .lineLimit(1)
    }

    /// Send to Claude in red glass, with keep or drop everything beside it, floating like the home dock.
    private func dock(_ cut: CutSet) -> some View {
        let kept = cut.kept
        let allKept = kept.count == cut.frames.count
        return GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button { store.setAll(!allKept, in: id) } label: {
                    Image(systemName: allKept ? "circle.slash" : "checkmark.circle")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.cInk)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(allKept ? "Drop all" : "Keep all")

                Button {
                    if kept.count > Self.batch { chooseBatch = true } else { sharing = kept.map { store.url($0, in: cut) } }
                } label: {
                    HStack(spacing: 8) {
                        Mark(color: .white).frame(width: 22)
                        Text(kept.isEmpty ? "Nothing kept" : "Send \(kept.count) to Claude").font(.app(16.5, .bold))
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(.white).padding(.horizontal, 10).frame(height: 34)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.cRed)
                .disabled(kept.isEmpty)
            }
        }
        .animation(.snappy(duration: 0.2), value: kept.count)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, Inset.container)
        .padding(.bottom, 6)
    }

    private func progressBar(_ cut: CutSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.cSurface2)
                    Rectangle().fill(Color.cRed).frame(width: geo.size.width * (store.progress[id] ?? 0))
                }
            }
            .frame(height: 3)
            Text("Cutting · \(cut.frames.count) frames so far").font(.mono(11)).foregroundStyle(Color.cMute)
        }
    }
}

/// A frame on the contact sheet at its own shape, with its number and time printed under it. Dropped frames are
/// sliced through and dimmed.
private struct FrameCell: View {
    var url: URL
    var frame: Frame
    var number: Int
    var aspect: CGFloat
    var toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Color.cSurface2
                .aspectRatio(aspect, contentMode: .fit)
                .overlay { FrameImage(url: url, side: 360) }
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .mask { if frame.kept { Rectangle() } else { SliceShape() } }
                .opacity(frame.kept ? 1 : 0.28)
                .overlay(alignment: .topTrailing) {
                    Button(action: toggle) {
                        ZStack {
                            Circle().fill(frame.kept ? Color.cRed : Color.black.opacity(0.45))
                            Circle().strokeBorder(.white, lineWidth: 1.2)
                            if frame.kept { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white) }
                        }
                        .frame(width: 20, height: 20)
                        .padding(5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(frame.kept ? "Drop frame \(number)" : "Keep frame \(number)")
                }
                .sensoryFeedback(.selection, trigger: frame.kept)
            HStack(spacing: 0) {
                Text(String(format: "%02d", number)).foregroundStyle(Color.cMute)
                Spacer(minLength: 4)
                Text(timecode(frame.time)).foregroundStyle(frame.kept ? Color.cInk : Color.cMute).strikethrough(!frame.kept)
            }
            .font(.mono(10.5))
        }
        .animation(.snappy(duration: 0.2), value: frame.kept)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Frame \(number) at \(timecode(frame.time)), \(frame.kept ? "kept" : "dropped")")
    }
}

/// The frame with a diagonal band cut out of it, the same cut as the logo.
struct SliceShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: r.origin); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.38)); p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.56))
        p.closeSubpath()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.61)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.43))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Loads a frame from disk at a small size, off the main thread.
struct FrameImage: View {
    var url: URL
    var side: CGFloat
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
        }
        .task(id: url) {
            let url = url, side = side
            image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: url.path).flatMap { img in
                    img.preparingThumbnail(of: CGSize(width: side, height: side * img.size.height / max(1, img.size.width)))
                }
            }.value
        }
    }
}

/// One frame full screen: swipe through them, keep or drop each, and a strip of every frame underneath to see where
/// you are and jump about. Zooming works like Photos: as you pinch, the frame grows out of its place, the page dims
/// towards black and everything else fades with it; let go before it's zoomed much and it springs back. A single tap
/// hides or shows the rest.
private struct FrameViewer: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var id: String
    @State var start: Int?
    /// 0 at rest, 1 once zoomed well in; the dim and the fade follow it as you pinch.
    @State private var zoom: CGFloat = 0
    @State private var bare = false

    init(id: String, start: Int) { self.id = id; _start = State(initialValue: start) }

    private var dim: CGFloat { bare ? 1 : zoom }

    var body: some View {
        if let cut = store.cut(id) {
            let current = cut.frames.first { $0.id == start } ?? cut.frames.first
            let n = current.flatMap { c in cut.frames.firstIndex { $0.id == c.id } } ?? 0
            GeometryReader { geo in
                let top = geo.safeAreaInsets.top, bottom = geo.safeAreaInsets.bottom
                let full = CGSize(width: geo.size.width, height: geo.size.height + top + bottom)
                let band = CGRect(x: Inset.container, y: top + 64, width: geo.size.width - 2 * Inset.container,
                                  height: geo.size.height - 64 - 150)
                let aspect = store.aspect(of: cut)
                ZStack(alignment: .topLeading) {
                    Color.cBg
                    Color.black.opacity(dim)

                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(cut.frames) { frame in
                                ZoomableFrame(url: store.url(frame, in: cut), aspect: aspect, rest: Self.fit(aspect, in: band),
                                              progress: { zoom = $0 },
                                              tap: { withAnimation(.smooth(duration: 0.25)) { bare.toggle() } })
                                    .opacity(frame.kept || dim > 0 ? 1 : 0.35)
                                    .frame(width: full.width, height: full.height)
                                    .id(frame.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollIndicators(.hidden)
                    .scrollDisabled(zoom > 0.01)
                    .scrollPosition(id: $start)
                    .frame(width: full.width, height: full.height)
                    // Once a pinch starts the frame comes up over the counter, Kept and the strip as they fade.
                    .zIndex(zoom > 0.001 ? 2 : 0)

                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            if let current {
                                (Text("\(n + 1) of \(cut.frames.count)").foregroundStyle(Color.cInk)
                                    + Text("  ·  \(timecode(current.time))").foregroundStyle(Color.cMute))
                                    .font(.app(15, .semibold))
                                    .contentTransition(.numericText())
                            }
                            Spacer()
                            Button { dismiss() } label: {
                                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.cInk)
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Close")
                        }
                        .padding(.leading, Inset.text).padding(.trailing, Inset.container)
                        Spacer(minLength: 0)
                        if let current { keepButton(current) }
                        strip(cut).padding(.top, 14)
                    }
                    .padding(.top, top + 8).padding(.bottom, bottom + 6)
                    .frame(width: full.width, height: full.height)
                    .opacity(1 - min(1, dim * 1.6))
                    .allowsHitTesting(dim < 0.05)
                    .zIndex(1)
                }
                .ignoresSafeArea()
            }
            .statusBarHidden(dim > 0.5)
            .animation(.snappy(duration: 0.2), value: start)
            .onChange(of: start) { zoom = 0 }
            #if DEBUG
            .onAppear { if ProcessInfo.processInfo.environment["CUT_FRAME"] == "bare" { bare = true } }
            #endif
        }
    }

    /// The largest rect of this shape that fits the band, centred in it.
    private static func fit(_ aspect: CGFloat, in band: CGRect) -> CGRect {
        var size = band.size
        if band.width / max(band.height, 1) > aspect { size.width = band.height * aspect } else { size.height = band.width / aspect }
        return CGRect(x: band.midX - size.width / 2, y: band.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// Kept in red glass, dropped in clear glass.
    @ViewBuilder private func keepButton(_ frame: Frame) -> some View {
        let label = Label(frame.kept ? "Kept" : "Dropped", systemImage: frame.kept ? "checkmark.circle.fill" : "circle.slash")
            .font(.app(15, .semibold))
            .foregroundStyle(frame.kept ? .white : Color.cInk)
            .padding(.horizontal, 6).frame(height: 30)
        Group {
            if frame.kept {
                Button { store.toggle(frame, in: id) } label: { label }.buttonStyle(.glassProminent).tint(Color.cRed)
            } else {
                Button { store.toggle(frame, in: id) } label: { label }.buttonStyle(.glass)
            }
        }
        .sensoryFeedback(.selection, trigger: frame.kept)
        .accessibilityHint(frame.kept ? "Tap to drop this frame" : "Tap to keep this frame")
    }

    /// Every frame small, the one showing outlined in red and dropped ones dimmed; tap to jump.
    private func strip(_ cut: CutSet) -> some View {
        let aspect = store.aspect(of: cut)
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 5) {
                    ForEach(cut.frames) { frame in
                        let on = frame.id == start
                        FrameImage(url: store.url(frame, in: cut), side: 120)
                            .frame(width: 56 * aspect, height: 56)
                            .background(Color.cSurface2)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .opacity(frame.kept ? 1 : 0.3)
                            .overlay {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(on ? Color.cRed : .clear, lineWidth: 2).padding(-2)
                            }
                            .padding(2)
                            .id(frame.id)
                            .onTapGesture { start = frame.id }
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.horizontal, Inset.container)
            }
            .scrollIndicators(.hidden)
            .frame(height: 62)
            .onAppear { proxy.scrollTo(start, anchor: .center) }
            .onChange(of: start) { _, now in withAnimation(.snappy) { proxy.scrollTo(now, anchor: .center) } }
        }
    }
}

/// A frame that zooms like Photos. The scroll view fills the screen; at rest the picture sits shrunk into its place on
/// the page (the minimum zoom) with rounded corners, and pinching grows it out from there to the whole screen and past
/// it. `progress` runs 0 to 1 over the first stretch of zoom, for the dim. Letting go short of that springs back.
/// At rest nothing scrolls, so swipes page.
private struct ZoomableFrame: UIViewRepresentable {
    var url: URL
    var aspect: CGFloat
    /// Where the picture sits at rest, in screen points.
    var rest: CGRect
    var progress: (CGFloat) -> Void = { _ in }
    var tap: () -> Void = {}

    func makeUIView(context: Context) -> ZoomScroll {
        let scroll = ZoomScroll()
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.bouncesZoom = true
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.decelerationRate = .fast
        scroll.delegate = context.coordinator
        scroll.backgroundColor = .clear
        scroll.image.contentMode = .scaleAspectFill
        scroll.image.clipsToBounds = true
        scroll.image.layer.cornerCurve = .continuous
        scroll.addSubview(scroll.image)
        scroll.onLayout = { [weak coordinator = context.coordinator] in coordinator?.place($0) }
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTap))
        single.require(toFail: double)
        scroll.addGestureRecognizer(single)
        load(into: scroll.image)
        return scroll
    }

    func updateUIView(_ scroll: ZoomScroll, context: Context) {
        let c = context.coordinator
        let moved = c.parent.rest != rest || c.parent.aspect != aspect
        let newImage = c.parent.url != url
        c.parent = self
        if newImage { load(into: scroll.image) }
        if moved || newImage { scroll.lastSize = .zero; scroll.setNeedsLayout() }
    }

    private func load(into view: UIImageView) {
        let url = url
        Task.detached(priority: .userInitiated) {
            let image = UIImage(contentsOfFile: url.path)
            await MainActor.run { view.image = image }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class ZoomScroll: UIScrollView {
        let image = UIImageView()
        var lastSize = CGSize.zero
        var onLayout: ((ZoomScroll) -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            if bounds.size != lastSize, bounds.width > 0 { lastSize = bounds.size; onLayout?(self) }
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableFrame
        /// The zoom at rest: the picture at its place on the page.
        private var restScale: CGFloat = 1
        private var lastProgress: CGFloat = 0
        init(_ parent: ZoomableFrame) { self.parent = parent }

        /// Sizes the picture to fill the screen at zoom 1, then sets the rest zoom so it shrinks into its place.
        func place(_ scroll: ZoomScroll) {
            let screen = scroll.bounds.size
            let a = parent.aspect
            let base = screen.width / screen.height > a
                ? CGSize(width: screen.height * a, height: screen.height)
                : CGSize(width: screen.width, height: screen.width / a)
            scroll.zoomScale = 1
            scroll.image.frame = CGRect(origin: .zero, size: base)
            scroll.contentSize = base
            restScale = min(1, parent.rest.width / base.width)
            scroll.minimumZoomScale = restScale
            scroll.maximumZoomScale = max(4, restScale * 6)
            scroll.zoomScale = restScale
            centre(scroll)
        }

        /// How far into the zoom we are: 0 at rest, 1 at the screen-filling size (or 1.6× rest, if that's smaller).
        private func amount(_ scroll: UIScrollView) -> CGFloat {
            let full = max(1, restScale * 1.6)
            return min(1, max(0, (scroll.zoomScale - restScale) / (full - restScale)))
        }

        /// Keeps the picture centred on its place at rest, drifting to the middle of the screen as it zooms.
        private func centre(_ scroll: UIScrollView) {
            let p = amount(scroll)
            let size = scroll.contentSize, screen = scroll.bounds.size
            let mid = CGPoint(x: parent.rest.midX + (screen.width / 2 - parent.rest.midX) * p,
                              y: parent.rest.midY + (screen.height / 2 - parent.rest.midY) * p)
            let left = size.width < screen.width ? max(0, min(screen.width - size.width, mid.x - size.width / 2)) : 0
            let top = size.height < screen.height ? max(0, min(screen.height - size.height, mid.y - size.height / 2)) : 0
            scroll.contentInset = UIEdgeInsets(top: top, left: left,
                                               bottom: max(0, screen.height - size.height - top),
                                               right: max(0, screen.width - size.width - left))
            let corner: CGFloat = 10 * (1 - p)
            (scroll as? ZoomScroll)?.image.layer.cornerRadius = corner / max(scroll.zoomScale, 0.01)
            if abs(p - lastProgress) > 0.001 { lastProgress = p; parent.progress(p) }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? ZoomScroll)?.image }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { centre(scrollView) }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            // Barely zoomed: spring back to the page, like Photos.
            if scale < restScale * 1.35 { springBack(scrollView) }
        }

        private func springBack(_ scroll: UIScrollView) {
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
                scroll.zoomScale = self.restScale
                self.centre(scroll)
            }
            parent.progress(0); lastProgress = 0
        }

        @objc func singleTap() { parent.tap() }

        @objc func doubleTap(_ tap: UITapGestureRecognizer) {
            guard let scroll = tap.view as? ZoomScroll else { return }
            if scroll.zoomScale > restScale * 1.01 {
                springBack(scroll)
            } else {
                let target = max(1, restScale * 2.5)
                let point = tap.location(in: scroll.image)
                let size = CGSize(width: scroll.bounds.width / target, height: scroll.bounds.height / target)
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
                    scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                           width: size.width, height: size.height), animated: false)
                    self.centre(scroll)
                }
            }
        }
    }
}

private struct Working: View {
    var text: String
    var body: some View {
        VStack(spacing: 16) {
            OrbView(kind: .searching, size: 72)
            Text(text).font(.app(14)).foregroundStyle(Color.cMute).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

private struct Failed: View {
    var text: String
    var retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Couldn't finish this cut").font(.app(16, .semibold))
            Text(text).font(.app(14)).foregroundStyle(Color.cMute)
            Button("Try again", action: retry).buttonStyle(PrimaryButtonStyle())
        }
        .padding(.top, 20)
    }
}

/// The system share sheet with the frame files, so they arrive in Claude as images.
struct ActivitySheet: UIViewControllerRepresentable {
    var items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension CutSet.Source {
    var icon: String {
        switch self {
        case .tour: "record.circle"
        case .link: "link"
        case .video: "film"
        }
    }
}

extension CutSet {
    /// A tour without a name goes by when it was recorded; anything else by its title.
    var displayTitle: String {
        source == .tour && (title.isEmpty || title == "Screen tour")
            ? created.formatted(.dateTime.weekday(.wide).hour().minute()) : title
    }

    /// The byline, unless it's an account number (older cuts kept Instagram's numeric id).
    var cleanByline: String? {
        guard let b = post?.handle ?? byline else { return nil }
        return b.dropFirst(b.hasPrefix("@") ? 1 : 0).allSatisfy(\.isNumber) ? nil : b
    }

    var hasName: Bool { !(source == .tour && (title.isEmpty || title == "Screen tour")) }

    /// "@someone · Instagram · 0:27 · 7 Nov", or "Screen tour · 0:33 · 11 Nov, 11:31 pm".
    var metaLine: String {
        let when = source == .tour
            ? created.formatted(.dateTime.day().month(.abbreviated).hour().minute())
            : (post?.posted.map { Date(timeIntervalSince1970: $0) } ?? created).formatted(.dateTime.day().month(.abbreviated))
        let who = source == .link ? cleanByline : nil
        return [who, sourceName, duration.map(timecode), when].compactMap { $0 }.joined(separator: " · ")
    }

    /// The row's first words, in ink: who posted it, or what it is.
    var rowLead: String {
        switch source {
        case .link: cleanByline ?? sourceName
        case .tour: "Screen tour"
        case .video: "Video"
        }
    }

    /// After the lead, muted: Reel, Post, Short, or when a tour was recorded.
    var rowTail: String? {
        switch source {
        case .tour: return hasName ? created.formatted(date: .omitted, time: .shortened) : nil
        case .video: return nil
        case .link:
            let path = link.flatMap { URL(string: $0)?.path() }?.lowercased() ?? ""
            let kind = path.contains("/reel") ? "Reel" : path.contains("/shorts") ? "Short" : path.hasPrefix("/p/") ? "Post"
                : path.contains("/video") ? "Video" : nil
            return cleanByline == nil ? kind : (kind ?? sourceName)
        }
    }

    /// Where it came from in a word: Screen tour, Video, or the site's name.
    var sourceName: String {
        switch source {
        case .tour: "Screen tour"
        case .video: "Video"
        case .link: Self.siteName(link) ?? "Link"
        }
    }

    /// Instagram, TikTok, YouTube, X, or the site's own first word.
    static func siteName(_ link: String?) -> String? {
        guard let host = link.flatMap({ URL(string: $0)?.host(percentEncoded: false) })?.lowercased() else { return nil }
        let known = ["instagram": "Instagram", "tiktok": "TikTok", "youtube": "YouTube", "youtu": "YouTube",
                     "x": "X", "twitter": "X", "facebook": "Facebook", "fb": "Facebook", "threads": "Threads", "vimeo": "Vimeo"]
        let parts = host.components(separatedBy: ".")
        let word = parts.first { !["www", "m", "vm", "vt", "mobile"].contains($0) } ?? host
        return known[word] ?? word.capitalized
    }
}

extension Post {
    /// "9 Nov 2026 · 1.2M views · 84K likes · 312 comments"
    var stats: String {
        func n(_ v: Int, _ word: String) -> String { "\(v.formatted(.number.notation(.compactName))) \(word)" }
        return ([posted.map { Date(timeIntervalSince1970: $0).formatted(.dateTime.day().month(.abbreviated).year()) }]
                + [views.map { n($0, "views") }, likes.map { n($0, "likes") }, comments.map { n($0, "comments") }])
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// The caption without the line already used as the title.
    func rest(after title: String) -> String? {
        guard var text = caption else { return nil }
        let first = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let shown = title.hasSuffix("…") ? String(title.dropLast()) : title
        if !shown.isEmpty, first.hasPrefix(shown) { text = String(text.dropFirst(first.count)) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

extension Store {
    /// Width over height of a cut's frames, read once from the first frame's header; screens and reels are tall.
    func aspect(of cut: CutSet) -> CGFloat {
        if let known = FrameAspect.cache[cut.id] { return known }
        guard let first = cut.frames.first,
              let src = CGImageSourceCreateWithURL(url(first, in: cut) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat, let h = props[kCGImagePropertyPixelHeight] as? CGFloat, h > 0
        else { return cut.source == .tour ? 9 / 19.5 : 9 / 16 }
        FrameAspect.cache[cut.id] = w / h
        return w / h
    }
}

@MainActor private enum FrameAspect { static var cache: [String: CGFloat] = [:] }
