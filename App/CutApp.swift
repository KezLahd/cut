import SwiftUI
import UIKit

@main
struct CutApp: App {
    @State private var store = Store()
    @State private var tour = TourController()
    @Environment(\.scenePhase) private var phase
    /// System, Light or Dark, chosen in Settings.
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(tour)
                .tint(.cRed)
                // Set on the window rather than with preferredColorScheme, which stays stuck on Dark when switched back
                // to System. Sheets follow the window.
                .task { applyAppearance() }
                .onChange(of: appearance) { applyAppearance() }
                .onAppear {
                    tour.onFinished = { [store] in store.collect() }
                    store.collect()
                }
                .onChange(of: phase) { _, now in
                    if now == .active {
                        tour.refresh()
                        store.collect()
                    }
                }
                .onOpenURL { url in
                    // cut://open after the share sheet, or a link handed straight to Cut.
                    if url.scheme == "cut" { store.collect() } else { store.path = [store.addLink(url)] }
                }
        }
    }

    private func applyAppearance() {
        let style: UIUserInterfaceStyle = appearance == "light" ? .light : appearance == "dark" ? .dark : .unspecified
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
    }
}
