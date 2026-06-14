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
import LumitextCore

// Tees to the unified os.log AND ~/Library/Logs/Lumitext[-Dev]/lumitext.log.
private let logger = AppLog(category: "Activation")

@MainActor
final class ActivationManager: ObservableObject {
    /// The screensaver's display name as it appears in System Settings / PaperSaver.
    nonisolated static let saverModuleName = "LumitextSaver"

    @Published var isActiveSaver = false
    @Published var idleTimeSeconds = 0
    @Published var lastError: String?
    @Published var busy = false
    /// True while moveToApplications() copies the bundle — its own flag (not
    /// `busy`) so the activate button doesn't falsely show "Setting…".
    @Published var moving = false

    /// Each user action (activate / set idle / move) owns its OWN error slot, so
    /// one action's failure can never silently overwrite or clear another's — the
    /// banner shows the most recently reported one, and clearing it reveals any
    /// other still-pending failure underneath.
    private enum ErrorKind { case activation, idle, move }
    private var errorsByKind: [ErrorKind: String] = [:]
    /// Kinds in the order they were last reported (least → most recent), so the
    /// banner surfaces the freshest failure while older ones survive beneath it.
    private var errorOrder: [ErrorKind] = []

    private func report(_ message: String?, kind: ErrorKind) {
        errorOrder.removeAll { $0 == kind }
        if let message {
            errorsByKind[kind] = message
            errorOrder.append(kind)
        } else {
            errorsByKind[kind] = nil
        }
        lastError = errorOrder.last.flatMap { errorsByKind[$0] }
    }

    /// Focus-driven refreshes can fire in bursts (Cmd-Tab dances, Spotlight);
    /// PaperSaver re-reads system state each time, so coalesce them.
    private var lastRefreshAt: Date = .distantPast
    func refreshIfStale(olderThan interval: TimeInterval = 1.0) {
        guard Date().timeIntervalSince(lastRefreshAt) >= interval else { return }
        refresh()
    }
    /// False until refresh() has read the real system state — UI that reacts to
    /// idleTimeSeconds == 0 must wait for this, or it flashes at launch.
    @Published var stateLoaded = false

    private let paperSaver = PaperSaver()

    /// True when the app is running from /Applications (where pluginkit expects
    /// it). Case-insensitive: the boot volume is case-insensitive APFS, so the
    /// same bundle can legitimately be reported as /applications/… (Terminal
    /// `open`, scripts) — a case-sensitive test would falsely block activation.
    var isInApplicationsFolder: Bool {
        Self.isApplicationsPath(Bundle.main.bundlePath)
    }

    /// Pure so the gate is unit-testable without faking Bundle.main.
    nonisolated static func isApplicationsPath(_ path: String) -> Bool {
        path.range(of: "/Applications/", options: [.anchored, .caseInsensitive]) != nil
    }

    var embeddedExtensionPath: String? {
        Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("\(Self.saverModuleName).appex").path
    }

    func refresh() {
        lastRefreshAt = Date()
        isActiveSaver = paperSaver.getActiveScreensavers().contains(Self.saverModuleName)
        idleTimeSeconds = paperSaver.getIdleTime()
        stateLoaded = true
        // The saver became active (e.g. set externally via System Settings) —
        // a stored ACTIVATION-failure message is now contradicted by reality;
        // showing a green "Active" dot next to a red failure banner lies to
        // the user. Routed through report() so the kind-scoped clear (idle/move
        // failures are NOT contradicted by an active saver and must survive) is
        // expressed in exactly one place.
        if isActiveSaver { report(nil, kind: .activation) }
    }

    /// Register the embedded appex with pluginkit so it appears in System Settings.
    /// Runs the pluginkit process off the main thread so launch never beachballs.
    /// `surfaceErrors: false` for the launch-time auto-register: a red error
    /// banner before the user has done anything is alarming and would also
    /// linger (nothing clears it until the next explicit action).
    func registerExtension(surfaceErrors: Bool = true) async {
        guard let path = embeddedExtensionPath,
              FileManager.default.fileExists(atPath: path) else {
            logger.error("embedded appex missing from bundle")
            if surfaceErrors {
                report(String(localized: "embeddedSaverMissing",
                              defaultValue: "Embedded screensaver not found in app bundle."),
                       kind: .activation)
            }
            return
        }
        let status = await Self.runProcessOffMain("/usr/bin/pluginkit", ["-a", path])
        logger.notice("pluginkit -a exit=\(status)")
        // `pluginkit -a` exits 0 even when the registration is silently filtered
        // out (e.g. missing sandbox entitlement — see CLAUDE.md). A non-zero
        // status only means the process itself failed to run; the real
        // confirmation is the discovery poll in activate().
        if status != 0, surfaceErrors {
            report(String(localized: "registerFailed",
                          defaultValue: "Couldn't register the screensaver with macOS."),
                   kind: .activation)
        }
    }

    /// True once system discovery (directory scan + pluginkit) can see the saver.
    /// Off-main: PaperSaver's listing shells out to /usr/bin/pluginkit.
    private nonisolated static func saverVisibleToSystem() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            PaperSaver().listAvailableScreensavers().contains {
                // ScreensaverModule.identifier carries the appex FILENAME stem
                // (not the bundle ID), so both branches compare the module name.
                $0.name == saverModuleName || $0.identifier == saverModuleName
            }
        }.value
    }

    /// The full activation flow — register, then set as the active screensaver on
    /// every display. One busy window spans both steps so the UI's progress state
    /// covers the whole multi-second run.
    func activate() async {
        busy = true
        report(nil, kind: .activation)
        defer { busy = false }
        // Registering a non-/Applications copy would win pkd's single-path
        // election and shadow the correct install (the stale-election wedge the
        // whole dev loop guards against). Launch auto-registration is gated the
        // same way; the button is disabled too — this is defense in depth.
        guard isInApplicationsFolder else {
            report(String(localized: "moveBeforeActivate", defaultValue: """
            Move Lumitext to /Applications first — registering from this \
            location would make macOS load the wrong copy.
            """), kind: .activation)
            return
        }
        await registerExtension()
        // registerExtension reports failure via the .activation slot (it doesn't
        // throw); don't claim success by activating a stale registration on top
        // of it. Kind-scoped: a surviving idle/move banner (deliberately not
        // cleared above) must not abort an otherwise healthy activation.
        guard errorsByKind[.activation] == nil else { return }

        // `pluginkit -a` returns before the registration is queryable, and
        // PaperSaver re-discovers modules on every call — activating right away
        // can throw "Screensaver not found" (observed live on a first click).
        // Poll discovery briefly so activation never races its own registration.
        var visible = false
        for attempt in 1...10 {
            if await Self.saverVisibleToSystem() {
                visible = true
                logger.notice("saver discovery: visible after attempt \(attempt)")
                break
            }
            // Don't sleep after the final probe — we're about to give up anyway.
            if attempt < 10 { try? await Task.sleep(for: .milliseconds(400)) }
        }
        guard visible else {
            // The CLAUDE.md-documented failure mode: `pluginkit -a` exits 0 but
            // pkd silently filters the registration (e.g. missing sandbox
            // entitlement). Name it in the log for the next debugger.
            logger.error("saver never became discoverable after 10 polls — likely filtered from pkd (missing sandbox entitlement?)")
            report(String(localized: "saverNotDiscoverable", defaultValue: """
            macOS hasn't finished registering the screensaver. Try again in a \
            moment — if it keeps failing, log out and back in.
            """), kind: .activation)
            return
        }

        do {
            try await paperSaver.setScreensaverEverywhere(module: Self.saverModuleName)
            refresh()
            // PaperSaver verifies the write and AUTO-ROLLS-BACK on failure
            // WITHOUT throwing (writeWithAutoRollback) — a normal return with
            // isActiveSaver still false is a real failure, not success. Without
            // this check the button spins for seconds and then nothing happens.
            if !isActiveSaver {
                logger.error("activation rolled back: setScreensaverEverywhere returned but the saver is not active")
                report(String(localized: "activationRolledBack", defaultValue: """
                macOS rejected the change and restored the previous screen \
                saver. Try again — if it keeps failing, log out and back in.
                """), kind: .activation)
            }
        } catch {
            // PaperSaverKit's error strings are hardcoded English — interpolating
            // them produces mixed-language sentences for zh-Hans users. The
            // detail goes to the log (where the developer needs it); the user
            // sees a fully-localized sentence with the actionable advice.
            logger.error("setScreensaverEverywhere failed: \(error.localizedDescription)")
            report(String(localized: "setSaverFailed", defaultValue: """
            Couldn't set the screen saver. Try again — if it keeps failing, \
            log out and back in.
            """), kind: .activation)
        }
    }

    /// Manual fallback when programmatic activation can't complete: hand the
    /// user the actual System Settings pane so they can finish the job there.
    func openScreenSaverSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Set the idle delay before the screensaver starts (seconds; 0 = never).
    func setIdleTime(_ seconds: Int) {
        report(nil, kind: .idle)   // don't let an old, unrelated error linger next to this action
        do {
            try paperSaver.setIdleTime(seconds: seconds)
            idleTimeSeconds = seconds
        } catch {
            // English-only PaperSaverKit detail goes to the log, not the banner.
            logger.error("setIdleTime failed: \(error.localizedDescription)")
            report(String(localized: "idleTimeFailed",
                          defaultValue: "Couldn't change the idle delay. Try again in a moment."),
                   kind: .idle)
        }
    }

    /// Offer to relocate the app to /Applications, then relaunch from there.
    /// The bundle copy is tens of MB of file I/O — it runs off the main actor
    /// (a synchronous copy beachballed the window) while `moving` drives the
    /// button's progress state.
    func moveToApplications() async {
        guard !moving else { return }
        // Already in /Applications: the swap would copy the running bundle onto
        // itself (source == dest), needlessly removing and re-creating the live
        // install. The UI gates the button on this too, but guard here so any
        // direct/programmatic call is a safe no-op.
        guard !isInApplicationsFolder else { return }
        report(nil, kind: .move)
        moving = true
        defer { moving = false }

        let source = Bundle.main.bundlePath
        let dest = "/Applications/\(Bundle.main.bundleURL.lastPathComponent)"
        // Stage the copy first so a copy failure can never destroy an existing
        // /Applications install; the remove+rename window at the end is tiny.
        let staging = "/Applications/.Lumitext-staging-\(ProcessInfo.processInfo.processIdentifier).app"
        let failure = await Task.detached(priority: .userInitiated) {
            Self.stageAndSwap(source: source, dest: dest, staging: staging)
        }.value
        if let failure {
            logger.error("moveToApplications failed: \(failure)")
            report(failure, kind: .move)
            return
        }

        // Relaunch via a detached watchdog that waits for THIS process to
        // exit. A plain `open dest` races our own termination: while the old
        // instance is still alive, LaunchServices resolves the same bundle ID
        // to it, activates the dying process instead of launching the copy,
        // and the user ends up with nothing running. The watchdog retries the
        // open once after a short pause (the first launch of a /Applications
        // copy can be briefly blocked by Gatekeeper/translocation) — but it
        // ONLY ever opens `dest`, never the source. The move already succeeded,
        // so the source is a stale copy: reopening it would run the OLD bundle
        // while the user believes they're now in /Applications, leaving
        // isInApplicationsFolder false and trapping them in a repeating
        // "move to /Applications" prompt loop. (The genuinely-failed-move path
        // returns early above at `if let failure`, so it never reaches here —
        // there is no case where the source is the right thing to open.)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            #"""
            while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.1; done
            /usr/bin/open "$2" && exit 0
            /bin/sleep 1
            /usr/bin/open "$2"
            """#,
            "lumitext-relaunch",
            String(ProcessInfo.processInfo.processIdentifier),
            dest,
        ]
        do {
            try task.run()
        } catch {
            // The move ITSELF succeeded — /Applications has a valid copy — but
            // no watchdog means quitting now would leave nothing running and
            // nothing relaunching. Stay alive and tell the user instead.
            report(String(localized: "moveFailed",
                          defaultValue: "Couldn't move to /Applications: \(error.localizedDescription)"),
                   kind: .move)
            return
        }
        NSApp.terminate(nil)
    }

    /// A crash mid-move can orphan the PID-suffixed staging/backup copies in
    /// /Applications forever (multi-MB each). Sweep them at launch — but only
    /// those whose creating process is gone, so a concurrently-running move
    /// (second instance, dev script) is never raided.
    ///
    /// This method owns ONLY the side effects (enumerate /Applications, stat,
    /// kill-probe, remove). The two decisions it makes — "is this entry one of
    /// our leftovers, and what PID created it?" and "given that PID's liveness
    /// and the entry's age, should it go?" — are the pure helpers below, so the
    /// logic can be exercised without a real filesystem.
    nonisolated static func cleanupMoveLeftovers() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: "/Applications") else { return }
        for entry in entries {
            guard let pid = leftoverPID(forEntry: entry) else { continue }
            let path = "/Applications/\(entry)"
            // Age is unknowable when creationDate can't be read — pass nil so
            // the decision falls back to "treat as fresh" and never deletes on
            // the age arm alone (see shouldRemoveLeftover).
            let ageSeconds: TimeInterval? = {
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let created = attrs[.creationDate] as? Date else { return nil }
                return Date().timeIntervalSince(created)
            }()
            // "Process gone" must mean ESRCH specifically: kill() also fails
            // with EPERM when the PID is ALIVE but owned by another user, and
            // /Applications is admin-shared — another account's in-flight move
            // must not be raided. (Its leftovers still age out via the 24h arm.)
            let processAlive = !(kill(pid, 0) != 0 && errno == ESRCH)
            if shouldRemoveLeftover(processAlive: processAlive, ageSeconds: ageSeconds) {
                try? fm.removeItem(atPath: path)
                logger.notice("removed orphaned move leftover \(entry)")
            }
        }
    }

    /// Pure: recognize one of our move leftovers by name and extract the PID
    /// that created it. Staging entries look like
    /// `.Lumitext-staging-<pid>.app`; backups like `Lumitext.app.old-<pid>`.
    /// Returns nil for any other entry, and for a recognized prefix whose
    /// trailing token isn't a number (so a malformed/foreign name can never be
    /// mistaken for a leftover and swept).
    nonisolated static func leftoverPID(forEntry entry: String) -> pid_t? {
        let isStaging = entry.hasPrefix(".Lumitext-staging-") && entry.hasSuffix(".app")
        let isBackup = entry.hasPrefix("Lumitext.app.old-")
        guard isStaging || isBackup else { return nil }
        // Drop the staging ".app" suffix so the PID is the last "-" token;
        // backups already end in the PID.
        let stem = isStaging ? String(entry.dropLast(4)) : entry
        guard let pidToken = stem.split(separator: "-").last,
              let pid = pid_t(pidToken) else { return nil }
        return pid
    }

    /// Pure: given the creating PID's liveness and the entry's age (nil when
    /// the age couldn't be read), decide whether to sweep the leftover.
    ///
    /// Remove iff the process is gone OR the entry is older than 24h. PIDs
    /// recycle, so the age arm is the safety net: a recycled-PID coincidence
    /// must not preserve garbage forever. When age is UNKNOWABLE, bias toward
    /// KEEPING — treating an unreadable age as ∞ would fire the age arm
    /// unconditionally and delete even live-process leftovers (hijacking another
    /// account's in-flight staging). So nil age contributes nothing; deletion
    /// then rests solely on "process confirmed gone (ESRCH)".
    nonisolated static func shouldRemoveLeftover(processAlive: Bool, ageSeconds: TimeInterval?) -> Bool {
        let tooOld = (ageSeconds ?? 0) > 24 * 3600
        return !processAlive || tooOld
    }

    /// The blocking file I/O of the move, off the main actor. Returns a
    /// localized error message, or nil when the verified copy sits at `dest`.
    /// The displaced install is moved ASIDE (not deleted) until the swap fully
    /// succeeds, so no failure mode can leave /Applications without a working
    /// app — a failed move-in restores the previous install.
    /// internal (not private): all paths are parameters, so the app test
    /// target drives the whole algorithm against temp directories.
    nonisolated static func stageAndSwap(source: String, dest: String, staging: String) -> String? {
        let fm = FileManager.default
        let backup = dest + ".old-\(ProcessInfo.processInfo.processIdentifier)"
        func restoreBackup() {
            if fm.fileExists(atPath: backup), !fm.fileExists(atPath: dest) {
                try? fm.moveItem(atPath: backup, toPath: dest)
            }
        }
        do {
            try? fm.removeItem(atPath: staging)
            try fm.copyItem(atPath: source, toPath: staging)
            if fm.fileExists(atPath: dest) {
                try? fm.removeItem(atPath: backup)
                try fm.moveItem(atPath: dest, toPath: backup)
            }
            do {
                try fm.moveItem(atPath: staging, toPath: dest)
            } catch {
                restoreBackup()
                throw error
            }
            // Sanity-check the moved copy is launchable BEFORE quitting: once we
            // terminate, no surviving process can report a broken copy — the
            // user would be left with no window and no error at all. The
            // executable name comes from the running bundle, not a literal, so
            // a PRODUCT_NAME change can't silently break this check.
            let executableName = Bundle.main.executableURL?.lastPathComponent ?? "Lumitext"
            let executable = "\(dest)/Contents/MacOS/\(executableName)"
            guard fm.isExecutableFile(atPath: executable) else {
                try? fm.removeItem(atPath: dest)
                restoreBackup()
                return String(localized: "movedCopyInvalid",
                              defaultValue: "Couldn't move to /Applications: the copied app is incomplete.")
            }
            try? fm.removeItem(atPath: backup)
            return nil
        } catch {
            try? fm.removeItem(atPath: staging)
            restoreBackup()
            return String(localized: "moveFailed",
                          defaultValue: "Couldn't move to /Applications: \(error.localizedDescription)")
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
