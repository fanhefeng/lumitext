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
    @StateObject private var model = AppModel()
    @StateObject private var activation = ActivationManager()

    var body: some Scene {
        WindowGroup {
            MainView(model: model, activation: activation)
                .task {
                    activation.refresh()
                    // Auto-register the embedded saver so it shows up in System Settings.
                    if activation.isInApplicationsFolder {
                        activation.registerExtension()
                    }
                }
        }
        .windowResizability(.contentMinSize)
    }
}
