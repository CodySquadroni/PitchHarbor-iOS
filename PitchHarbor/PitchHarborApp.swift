// Application entry point and lifetime of the shared CoachStore.
// Debug launch arguments select disposable test fixtures; normal launches load local data.

import SwiftUI

@main
struct PitchHarborApp: App {
    @State private var store: CoachStore = {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--app-store-capture") {
                return PreviewFixtures.appStoreStore()
            }
            if ProcessInfo.processInfo.arguments.contains("--preview-subs") { return PreviewFixtures.smartSubsStore() }
            if ProcessInfo.processInfo.arguments.contains("--preview-match") { return PreviewFixtures.matchStore() }
            if ProcessInfo.processInfo.arguments.contains("--uitesting-setup") {
                let url = URL.temporaryDirectory.appending(path: "PitchHarbor-setup-ui-test.json")
                if ProcessInfo.processInfo.arguments.contains("--reset-setup-test") {
                    try? FileManager.default.removeItem(at: url)
                }
                return CoachStore(fileURL: url)
            }
            if ProcessInfo.processInfo.arguments.contains("--uitesting")
                || ProcessInfo.processInfo.arguments.contains("--preview-board")
                || ProcessInfo.processInfo.arguments.contains("--preview-launch")
            {
                return CoachStore(sample: true)
            }
        #endif
        return CoachStore()
    }()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--preview-launch") {
                        LaunchScreenPreview().ignoresSafeArea()
                    } else {
                        StartupView().environment(store)
                    }
                #else
                    StartupView().environment(store)
                #endif
            }
            .tint(Palette.action)
            .onChange(of: phase) { _, newValue in
                if newValue != .active { store.checkpoint() }
            }
        }
    }
}
