//
//  LumitextApp.swift
//  Lumitext
//
//  Host app entry point. Owns the model + activation manager, refreshes activation
//  state on appear, and registers the embedded screensaver extension on first launch.
//

import SwiftUI

@main
struct LumitextApp: App {
    // Snapshot mode (LUMITEXT_SNAPSHOT_OUT) captures the real window to PNG and exits.
    @NSApplicationDelegateAdaptor(SnapshotAppDelegate.self) private var snapshotDelegate
    // As a TEST_HOST, this process is launched by xcodebuild test — it must
    // not touch the PRODUCTION /Users/Shared channel (on a fresh machine the
    // eager onboarding save would write a real config.json). XCTest sets this
    // env var in the host process.
    @StateObject private var model = AppModel(
        persist: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil)
    @StateObject private var activation = ActivationManager()

    var body: some Scene {
        WindowGroup {
            MainView(model: model, activation: activation)
                .task {
                    activation.refresh()
                    // Off-main housekeeping: a crash mid-move can orphan multi-MB
                    // staging/backup bundles in /Applications.
                    Task.detached(priority: .utility) { ActivationManager.cleanupMoveLeftovers() }
                    // Auto-register the embedded saver so it shows up in System
                    // Settings. Silent on failure: a red error banner before the
                    // user has done anything would alarm and then linger.
                    if activation.isInApplicationsFolder {
                        await activation.registerExtension(surfaceErrors: false)
                    }
                }
                // Re-sync when the user comes back from System Settings — the
                // active-saver dot and idle Picker otherwise show launch-time
                // values forever after an external change. Fonts installed
                // mid-session appear on the same signal. Throttled: focus
                // events fire in bursts (Cmd-Tab dances) and each refresh
                // re-reads system state on the main actor.
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification)) { _ in
                    activation.refreshIfStale()
                    model.refreshFontFamilies()
                }
        }
        .windowResizability(.contentMinSize)
        // Single-document config tool: a second window adds nothing and would
        // run duplicate registration tasks — remove File > New Window.
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
