import SwiftUI

/// Settings in the iPhone's own grouped style: appearance, how videos and tours are cut, link fetching, and
/// Recently deleted.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    @Environment(TourController.self) private var tour
    @AppStorage("defaultInterval") private var interval = 2.0
    @AppStorage("defaultScene") private var scene = false

    @State private var repo = CloudConfig.repo
    @State private var token = ""
    @State private var hasToken = CloudConfig.token != nil
    @State private var check: (ok: Bool, text: String)?
    @State private var checking = false
    @State private var showDeleted = false

    /// 0 stands for Scene: a frame each time the picture changes.
    private static let videoStops: [Double] = [0, 0.5, 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10, 15, 20, 30]

    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        @Bindable var tour = tour
        NavigationStack {
            List {
                Section("Appearance") {
                    HStack {
                        ForEach(["system", "light", "dark"], id: \.self) { mode in
                            ModeTile(mode: mode, selected: appearance == mode) { appearance = mode }
                        }
                    }
                    .padding(.vertical, 8)
                    .sensoryFeedback(.selection, trigger: appearance)
                }

                Section {
                    Picker("Take a frame every", selection: Binding(get: { scene ? 0 : interval },
                                                                    set: { if $0 == 0 { scene = true } else { scene = false; interval = $0 } })) {
                        ForEach(Self.videoStops, id: \.self) { Text($0 == 0 ? "On each scene" : TourController.duration($0)).tag($0) }
                    }
                } header: {
                    Text("Videos and links")
                } footer: {
                    Text("For new cuts. Any cut can be changed afterwards from its page.")
                }

                Section {
                    Picker("Take a frame every", selection: $tour.interval) {
                        ForEach(TourController.intervals, id: \.self) { Text($0 == 0 ? "On each change" : TourController.duration($0)).tag($0) }
                    }
                    Picker("Start after", selection: $tour.delay) {
                        ForEach(TourController.delays, id: \.self) { Text($0 == 0 ? "Straight away" : TourController.duration($0)).tag($0) }
                    }
                } header: {
                    Text("Screen tours")
                } footer: {
                    Text("The tour sheet starts from these each time.")
                }

                Section {
                    LabeledContent("Status") {
                        HStack(spacing: 7) {
                            Circle().fill(statusOK ? Color.green : Color.cRed).frame(width: 8, height: 8)
                            Text(statusText).lineLimit(1)
                        }
                    }
                    LabeledContent("Repo") {
                        TextField("owner/cut-fetcher", text: $repo)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    LabeledContent("Token") {
                        SecureField(hasToken ? "Saved" : "Paste a token", text: $token)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Button(checking ? "Checking…" : "Save and check") { save() }.disabled(checking)
                    Link(destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!) {
                        LabeledContent("Get a token") { Image(systemName: "arrow.up.forward").font(.footnote.weight(.semibold)) }
                    }
                    .tint(Color.cInk)
                } header: {
                    Text("Link fetching")
                } footer: {
                    Text("Reels and video links are fetched by a private GitHub workflow running yt-dlp. It only sees what a logged-out visitor sees and never signs in to Instagram or TikTok. Make a fine-grained token for just \(repo) with Actions set to Read and write.")
                }

                Section("Library") {
                    Button { showDeleted = true } label: {
                        LabeledContent("Recently deleted") {
                            HStack(spacing: 6) {
                                Text(store.deleted.isEmpty ? "Empty" : "\(store.deleted.count)")
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .tint(Color.cInk)
                }

                Section {
                } footer: {
                    Text("Version \(version)\nDeleted cuts are kept for 30 days.")
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showDeleted) { DeletedView() }
        }
        .tint(Color.cRed)
    }

    private var statusOK: Bool { check?.ok ?? hasToken }
    private var statusText: String {
        check?.text ?? (hasToken ? "On" : "Needs a token")
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    private func save() {
        CloudConfig.repo = repo
        if !token.isEmpty { CloudConfig.token = token.trimmingCharacters(in: .whitespacesAndNewlines); token = "" }
        hasToken = CloudConfig.token != nil
        guard let fetcher = CloudFetcher.configured else { check = (false, "Paste a token first."); return }
        checking = true
        Task {
            do { try await fetcher.check(); check = (true, "Connected to \(CloudConfig.repo)") }
            catch { check = (false, error.localizedDescription) }
            checking = false
        }
    }
}

/// System, Light or Dark as a little phone in Cut's colours: the page, a red mark, a strip of frames.
private struct ModeTile: View {
    let mode: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            phone
                .padding(3)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? Color.cRed : .clear, lineWidth: 2.5)
                }
            Text(mode.capitalized)
                .font(.footnote.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.cInk : Color.cMute)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.subheadline)
                .foregroundStyle(selected ? Color.cRed : Color.cMute.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.capitalized)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { action() }
    }

    private var phone: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return ZStack {
            switch mode {
            case "light": screen(dark: false)
            case "dark": screen(dark: true)
            default:
                screen(dark: false).overlay(alignment: .trailing) {
                    screen(dark: true).frame(width: 27, alignment: .trailing).clipped()
                }
            }
        }
        .frame(width: 54, height: 92)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.cInk.opacity(0.15)) }
    }

    private func screen(dark: Bool) -> some View {
        let bg = Color(white: dark ? 0.07 : 0.97)
        let ink = Color(white: dark ? 0.95 : 0.07)
        let frame = Color(white: dark ? 0.2 : 0.85)
        return VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(Color.cRed).frame(width: 16, height: 5)
            Capsule().fill(ink).frame(width: 34, height: 4)
            HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 1.5).fill(frame).frame(width: 12, height: 20) } }
            Capsule().fill(ink).frame(width: 30, height: 4).padding(.top, 4)
            HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 1.5).fill(frame).frame(width: 12, height: 20) } }
        }
        .padding(6).padding(.top, 6)
        .frame(width: 54, height: 92, alignment: .topLeading)
        .background(bg)
    }
}
