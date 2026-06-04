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

@MainActor
final class AppModel: ObservableObject {
    @Published var config: LumitextConfig
    /// Non-nil when persistence is degraded (e.g. /Users/Shared/Lumitext could not
    /// be created). UI still works; the warning is shown under the preview.
    @Published var persistenceWarning: String?

    /// All installed font families, with "" (system font) first.
    let fontFamilies: [String]

    private let store: ConfigStore?
    private var cancellables = Set<AnyCancellable>()

    init(persist: Bool = true) {
        // System font is represented as "" in the model; show it as a friendly label.
        fontFamilies = [""] + NSFontManager.shared.availableFontFamilies.sorted()

        var warning: String?
        if persist {
            // One-time: bring over a config saved by the earlier App-Group builds
            // (the group container is unreadable for the saver on Tahoe — ADR-0001).
            ConfigStore.migrateLegacyConfigIfNeeded()
            do {
                try ConfigStore.ensureDirectoryExists()
            } catch {
                warning = "Couldn't create \(ConfigStore.sharedDirectory.path) — changes won't reach the screensaver (\(error.localizedDescription))"
            }
            store = ConfigStore.production()
        } else {
            store = nil
        }
        persistenceWarning = warning

        // Load BEFORE subscribing the autosave, so the initial persisted config can't
        // be clobbered by a save triggered from an async load completing after a user
        // edit. The host is non-sandboxed so this read is fast.
        config = store?.load() ?? .default

        // Debounced autosave: coalesce rapid edits (typing, slider drags) into one write.
        $config
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] cfg in self?.save(cfg) }
            .store(in: &cancellables)
    }

    private func save(_ cfg: LumitextConfig) {
        guard let store else { return }
        Task.detached(priority: .utility) {
            do {
                try store.save(cfg)
            } catch {
                await MainActor.run {
                    self.persistenceWarning = "Couldn't save settings: \(error.localizedDescription)"
                }
            }
        }
    }
}
