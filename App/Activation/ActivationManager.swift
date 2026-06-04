//
//  ActivationManager.swift
//  Lumitext
//
//  Registers the embedded screensaver extension with pluginkit and activates it
//  via PaperSaverKit. Enforces the "run from /Applications" rule because pluginkit
//  caches discovered locations and prefers /Applications — running from elsewhere
//  loads the wrong build and confuses users.
//

import Foundation
import AppKit
import PaperSaverKit
import os.log

private let logger = Logger(subsystem: "io.github.fanhefeng.lumitext", category: "Activation")

@MainActor
final class ActivationManager: ObservableObject {
    /// The screensaver's display name as it appears in System Settings / PaperSaver.
    static let saverModuleName = "LumitextSaver"
    static let saverBundleID = "io.github.fanhefeng.lumitext.saver"

    @Published var isActiveSaver = false
    @Published var idleTimeSeconds = 0
    @Published var lastError: String?
    @Published var busy = false
    /// False until refresh() has read the real system state — UI that reacts to
    /// idleTimeSeconds == 0 must wait for this, or it flashes at launch.
    @Published var stateLoaded = false

    private let paperSaver = PaperSaver()

    /// True when the app is running from /Applications (where pluginkit expects it).
    var isInApplicationsFolder: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    var embeddedExtensionPath: String? {
        Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("\(Self.saverModuleName).appex").path
    }

    func refresh() {
        isActiveSaver = paperSaver.getActiveScreensavers().contains(Self.saverModuleName)
        idleTimeSeconds = paperSaver.getIdleTime()
        stateLoaded = true
    }

    /// Register the embedded appex with pluginkit so it appears in System Settings.
    /// Runs the pluginkit process off the main thread so launch never beachballs.
    func registerExtension() async {
        guard let path = embeddedExtensionPath,
              FileManager.default.fileExists(atPath: path) else {
            lastError = "Embedded screensaver not found in app bundle."
            return
        }
        let status = await Self.runProcessOffMain("/usr/bin/pluginkit", ["-a", path])
        logger.notice("pluginkit -a exit=\(status)")
    }

    /// The full activation flow — register, then set as the active screensaver on
    /// every display. One busy window spans both steps so the UI's progress state
    /// covers the whole multi-second run.
    func activate() async {
        busy = true
        lastError = nil
        defer { busy = false }
        await registerExtension()
        // registerExtension reports failure via lastError (it doesn't throw);
        // don't claim success by activating a stale registration on top of it.
        guard lastError == nil else { return }
        do {
            try await paperSaver.setScreensaverEverywhere(module: Self.saverModuleName)
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Set the idle delay before the screensaver starts (seconds; 0 = never).
    func setIdleTime(_ seconds: Int) {
        do {
            try paperSaver.setIdleTime(seconds: seconds)
            idleTimeSeconds = seconds
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Offer to relocate the app to /Applications, then relaunch from there.
    func moveToApplications() {
        let fm = FileManager.default
        let dest = "/Applications/\(Bundle.main.bundleURL.lastPathComponent)"
        do {
            if fm.fileExists(atPath: dest) { try fm.removeItem(atPath: dest) }
            try fm.copyItem(atPath: Bundle.main.bundlePath, toPath: dest)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [dest]
            try task.run()
            NSApp.terminate(nil)
        } catch {
            lastError = "Couldn't move to /Applications: \(error.localizedDescription)"
        }
    }

    /// Run a process on a background queue and await its exit status, so the main
    /// (UI) thread is never blocked on waitUntilExit().
    private static func runProcessOffMain(_ path: String, _ args: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: path)
                task.arguments = args
                do {
                    try task.run()
                    task.waitUntilExit()
                    continuation.resume(returning: task.terminationStatus)
                } catch {
                    continuation.resume(returning: -1)
                }
            }
        }
    }
}
