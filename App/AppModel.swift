//
//  AppModel.swift
//  Lumitext
//
//  Holds the editable LumitextConfig and persists it to /Users/Shared/Lumitext
//  (the sole writer; the saver only reads). Persistence is resilient and saves run
//  off the main thread: if the directory can't be created, the UI keeps working
//  with an in-memory config and surfaces a status note rather than failing.
//

import SwiftUI
import Combine
import LumitextCore

// Tees to the unified os.log AND ~/Library/Logs/Lumitext[-Dev]/lumitext.log.
private let logger = AppLog(category: "AppModel")

@MainActor
final class AppModel: ObservableObject {
    @Published var config: LumitextConfig
    /// Non-nil when persistence is degraded (e.g. /Users/Shared/Lumitext could not
    /// be created). UI still works; the warning is shown under the preview.
    @Published var persistenceWarning: String?

    /// All installed font families, with "" (system font) first. Starts with
    /// just the system entry and fills in asynchronously: enumerating the font
    /// registry is a directory scan that doesn't belong on the launch path.
    /// Refreshed on app activation so fonts installed mid-session appear.
    @Published private(set) var fontFamilies: [String] = [""]

    private let store: ConfigStore?
    private var cancellables = Set<AnyCancellable>()
    /// The config most recently confirmed on disk — lets the quit-time flush
    /// detect a pending (debounced or still in-flight) edit it must not drop.
    private var lastPersisted: LumitextConfig?
    /// All disk writes go through one FIFO queue, so the synchronous quit-time
    /// flush enqueues last and is guaranteed to land after any async save.
    private static let saveQueue = DispatchQueue(
        label: "\(Identifiers.subsystem).AppModel.save", qos: .utility)

    /// `overrideStore` is the unit-test seam: an injected store (temp
    /// directory) replaces production directory prep entirely, so the init
    /// decision table and the flush path are testable without /Users/Shared.
    init(persist: Bool = true, overrideStore: ConfigStore? = nil) {
        var warning: String?
        var preparedStore: ConfigStore?
        if let overrideStore {
            preparedStore = overrideStore
        } else if persist {
            do {
                try ConfigStore.ensureDirectoryExists()
                preparedStore = ConfigStore.production()
            } catch let error as ConfigStoreError {
                // The directory exists but can't be TRUSTED: owned by another
                // account (its config is someone else's — presenting it as this
                // user's own settings would lie, and edits could never persist),
                // world-writable (a squat we must not write into), or a planted
                // symlink. Run fully in-memory on defaults — no load, no
                // autosave — and say so honestly. The English-only diagnostic
                // detail goes to the log, not the localized banner.
                logger.error("shared directory untrusted: \(error.localizedDescription)")
                warning = String(localized: "sharedDirUntrusted", defaultValue: """
                The shared settings folder is owned by another account on this \
                Mac (or isn't safe to use). Lumitext is showing default \
                settings; changes won't be saved or reach the screensaver.
                """)
            } catch {
                logger.error("shared directory prep failed: \(error.localizedDescription)")
                warning = String(localized: "sharedDirFailed", defaultValue: """
                Couldn't prepare \(ConfigStore.sharedDirectory.path) — changes \
                won't reach the screensaver (\(error.localizedDescription))
                """)
                // Creation failed but nothing distrusts the path itself — keep
                // the store so saveWithRetry can recover if the directory
                // becomes creatable later in the session.
                preparedStore = ConfigStore.production()
            }
        }
        // Load BEFORE subscribing the autosave, so the initial persisted config
        // can't be clobbered by a save racing a user edit. THREE-way, not
        // load(): the schemaVersion gate maps a NEWER config to .failed, and
        // the host must honor that contract end to end — showing defaults with
        // a LIVE autosave would overwrite the newer config on the first edit.
        var initialConfig = LumitextConfig.default
        var freshInstall = false
        switch preparedStore?.loadResult() {
        case .loaded(let c):
            initialConfig = c
        case .missing:
            freshInstall = true
        case .failed:
            // A config exists that this build can't read (written by a newer
            // Lumitext, or transiently unreadable). NEVER autosave over it —
            // run in-memory, like the untrusted-directory mode.
            preparedStore = nil
            warning = String(localized: "configUnreadable", defaultValue: """
            A saved configuration exists that this version of Lumitext can't \
            read — your changes won't be saved, so it won't be overwritten. \
            Update Lumitext, or delete \(ConfigStore.sharedDirectory.path) to start over.
            """)
        case nil:
            break
        }
        // The onboarding sample is localized HERE — Core has no string table,
        // so its "Hello, Lumitext" literal can't be. The eager save below
        // writes the localized text to disk, so the WYSIWYG saver greets a
        // zh-Hans user with the same words as the preview.
        if freshInstall {
            initialConfig.text = String(localized: "onboardingSampleText",
                                        defaultValue: "Hello, Lumitext")
        }

        store = preparedStore
        persistenceWarning = warning
        config = initialConfig
        // nil on a fresh install (nothing is on disk yet) so the quit-time
        // flush also covers the eager onboarding write below.
        lastPersisted = freshInstall ? nil : config

        // Debounced autosave: coalesce rapid edits (typing, slider drags) into one write.
        $config
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] cfg in self?.save(cfg) }
            .store(in: &cancellables)

        // Quit-time flush: without it, the 400ms debounce (and the async write
        // behind it) silently drops the user's last edit on Cmd-Q.
        NotificationCenter.default
            .publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.flushPendingSave() }
            .store(in: &cancellables)

        // Eager first write: the saver should show the localized onboarding
        // sample even before the user's first edit. Skipped when directory
        // prep already failed — the write is known-doomed, and its saveFailed
        // outcome would clobber the more specific sharedDirFailed warning.
        if freshInstall, warning == nil { save(config) }

        refreshFontFamilies(force: true)
    }

    /// Drops out-of-order outcome reports (outcome Tasks can in principle reach
    /// the main actor out of order, so each outcome carries its sequence) — the
    /// warning always reflects the LATEST write. The sequencing contract lives,
    /// and is unit-tested, in LumitextCore.
    private var outcomeGate = SaveOutcomeGate()

    /// Coalesces focus-burst rescans and orders out-of-order scan results.
    private var fontRefreshGeneration = 0
    private var lastFontRefreshAt = Date.distantPast

    /// Re-list installed families off the main thread ("" = system font first).
    /// Focus events fire in bursts (Cmd-Tab, Spotlight dismiss); the installed
    /// font set changes far more slowly, so coalesce — each rescan is a full font
    /// registry walk plus a cache wipe. `force` bypasses the throttle for the
    /// launch-time fill.
    func refreshFontFamilies(force: Bool = false) {
        if !force, Date().timeIntervalSince(lastFontRefreshAt) < 2 { return }
        lastFontRefreshAt = Date()
        fontRefreshGeneration += 1
        let generation = fontRefreshGeneration
        Task.detached(priority: .userInitiated) {
            let families = [""] + NSFontManager.shared.availableFontFamilies.sorted()
            await MainActor.run { [weak self] in
                guard let self else { return }
                // Drop a scan a newer one has already superseded: an older
                // enumeration finishing late must not overwrite the fresher list
                // or wipe verdicts just computed for it (the same out-of-order
                // hazard SaveOutcomeGate guards on the save path).
                guard generation == self.fontRefreshGeneration else { return }
                // Invalidate UNCONDITIONALLY: a same-named font can be replaced
                // (new file location/faces) without the family LIST changing,
                // so gating invalidation on list equality would keep stale
                // memoized verdicts until relaunch.
                NSFont.lumitextInvalidateFamilyCache()
                FontCatalog.invalidate()
                guard self.fontFamilies != families else { return }
                self.fontFamilies = families
            }
        }
    }

    private func save(_ cfg: LumitextConfig) {
        guard let store else { return }
        let seq = outcomeGate.nextSequence()
        Self.saveQueue.async { [weak self] in
            // Only Sendable values cross the queue→MainActor boundary: the
            // thrown `any Error` need not be Sendable (Swift 5 mode just
            // doesn't diagnose it), and the UI only needs the description.
            var failure: String?
            do {
                // saveWithRetry re-verifies directory trust on every write and
                // recreates a vanished directory — unit-tested in Core.
                try store.saveWithRetry(cfg)
            } catch {
                failure = error.localizedDescription
            }
            Task { @MainActor in self?.applyOutcome(seq: seq, savedConfig: cfg, failure: failure) }
        }
    }

    /// internal (not private) for the app test target.
    func applyOutcome(seq: Int, savedConfig: LumitextConfig, failure: String?) {
        guard outcomeGate.admit(seq) else { return }   // stale — a newer write already reported
        if let failure {
            // The banner is transient; the log is the durable witness for the
            // most common failure a user will ever report.
            logger.error("autosave failed: \(failure)")
            persistenceWarning = String(localized: "saveFailed",
                                        defaultValue: "Couldn't save settings: \(failure)")
        } else {
            lastPersisted = savedConfig
            // A successful write supersedes any earlier persistence failure.
            persistenceWarning = nil
        }
    }

    /// Synchronously persist a pending edit before the process exits. FIFO on
    /// saveQueue means any earlier async save lands first; this write is final.
    /// `lastPersisted` is only advanced when the write actually succeeded — the
    /// app is quitting so there's no UI to warn, but the bookkeeping must not
    /// claim an unpersisted config reached disk.
    /// internal (not private) for the app test target.
    func flushPendingSave() {
        guard let store, config != lastPersisted else { return }
        let cfg = config
        // Enqueue async (still FIFO behind any in-flight save) and wait with a
        // BOUND: saveWithRetry does synchronous filesystem I/O (stat/lstat/ACL +
        // an atomic write, possibly a directory re-create), and a stalled
        // /Users/Shared — a network/encrypted home, or the wedged
        // containermanagerd lease CLAUDE.md warns about — would otherwise hang
        // the main thread inside `.sync` indefinitely and beachball the quit. A
        // healthy local write finishes in well under this; past it, give up and
        // let the process exit rather than freeze it.
        let done = DispatchSemaphore(value: 0)
        var succeeded = false
        Self.saveQueue.async {
            succeeded = (try? store.saveWithRetry(cfg)) != nil
            done.signal()
        }
        guard done.wait(timeout: .now() + 2) == .success else {
            logger.error("quit-time flush timed out (shared volume stalled?); the last edit may not have reached disk")
            return
        }
        if succeeded {
            lastPersisted = cfg
        } else {
            // No UI is left to warn at quit time, but the loss must not be
            // silent — the log is the only witness.
            logger.error("quit-time flush failed; the last edit did not reach disk")
        }
    }
}
