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
    }

    /// Register the embedded appex with pluginkit so it appears in System Settings.
    func registerExtension() {
        guard let path = embeddedExtensionPath,
              FileManager.default.fileExists(atPath: path) else {
            lastError = "Embedded screensaver not found in app bundle."
            return
        }
        runPluginkit(["-a", path])
    }

    /// Set Lumitext as the active screensaver on every display.
    func setAsScreensaverEverywhere() async {
        busy = true
        lastError = nil
        defer { busy = false }
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

    private func runPluginkit(_ args: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = args
        do {
            try task.run()
            task.waitUntilExit()
            logger.notice("pluginkit \(args.joined(separator: " "), privacy: .public) exit=\(task.terminationStatus)")
        } catch {
            lastError = error.localizedDescription
        }
    }
}
