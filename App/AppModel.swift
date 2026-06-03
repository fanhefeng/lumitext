//
//  AppModel.swift
//  Lumitext
//
//  Holds the editable LumitextConfig and persists it to the App Group container
//  (the sole writer; the saver only reads). Persistence is resilient and
//  off-the-main-thread: if the container is unavailable or slow, the UI keeps
//  working with an in-memory config and surfaces a status note rather than hanging.
//

import SwiftUI
import Combine
import LumitextCore

@MainActor
final class AppModel: ObservableObject {
    @Published var config: LumitextConfig
    /// Non-nil when persistence is unavailable (e.g. running unsandboxed without the
    /// App Group, or the container is wedged). UI still works; saves are skipped.
    @Published var persistenceWarning: String?

    /// All installed font families, with "" (system font) first.
    let fontFamilies: [String]

    private let store: ConfigStore?
    private var cancellables = Set<AnyCancellable>()

    init(persist: Bool = true) {
        // System font is represented as "" in the model; show it as a friendly label.
        fontFamilies = [""] + NSFontManager.shared.availableFontFamilies.sorted()

        if persist {
            store = try? ConfigStore.appGroup()
        } else {
            store = nil
        }
        if persist && store == nil {
            persistenceWarning = "App Group container unavailable — changes won't be saved to the screensaver."
        }

        // Load BEFORE subscribing the autosave, so the initial persisted config can't
        // be clobbered by a save triggered from an async load completing after a user
        // edit. The load is bounded (never hangs launch on a slow/wedged container).
        config = store?.load(timeout: 0.5) ?? .default

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
