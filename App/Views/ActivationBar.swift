//
//  ActivationBar.swift
//  Lumitext
//
//  Install/activation controls + the honest "lock screen" explanation and the
//  idle-time helper, restyled as a section card with a clear status dot.
//

import SwiftUI

struct ActivationBar: View {
    @ObservedObject var activation: ActivationManager

    /// Transient post-success confirmation on the button itself.
    @State private var justActivated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let idleChoices: [(LocalizedStringKey, Int)] = [
        ("1 min", 60), ("2 min", 120), ("5 min", 300),
        ("10 min", 600), ("20 min", 1200), ("Never", 0),
    ]

    /// The system value may be something we don't offer (set via System
    /// Settings, e.g. 3 min) — inject it so the Picker never shows a blank
    /// selection.
    private var pickerChoices: [(LocalizedStringKey, Int)] {
        let current = activation.idleTimeSeconds
        guard activation.stateLoaded,
              !idleChoices.contains(where: { $0.1 == current }) else { return idleChoices }
        let label: LocalizedStringKey = current % 60 == 0
            ? "\(current / 60) min"
            : "\(current) s"
        return idleChoices + [(label, current)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            if !activation.isInApplicationsFolder {
                moveNotice
            }

            HStack(spacing: Theme.s3) {
                activateButton

                HStack(spacing: 6) {
                    Circle()
                        .fill(activation.isActiveSaver ? Theme.ok : Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text(activation.isActiveSaver ? "Active" : "Not active")
                        .font(.system(size: 12))
                        .foregroundStyle(activation.isActiveSaver ? Color.primary : Color.secondary)
                }
                .animation(reduceMotion ? nil : Theme.selectAnim, value: activation.isActiveSaver)
                .help(activation.isActiveSaver ? Text("Active") : Text("Not active"))
                // One labeled status element — a bare "Active" Text floating in
                // the VoiceOver order doesn't say active WHAT.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Screen saver status"))
                .accessibilityValue(activation.isActiveSaver ? Text("Active") : Text("Not active"))

                Spacer(minLength: 0)

                HStack(spacing: Theme.s2) {
                    Text("Start after")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        // The Picker carries its own accessibilityLabel below;
                        // leaving this visual label visible to VoiceOver makes
                        // it announce "Start after" twice.
                        .accessibilityHidden(true)
                    Picker("", selection: Binding(
                        get: { activation.idleTimeSeconds },
                        set: { activation.setIdleTime($0) }
                    )) {
                        ForEach(pickerChoices, id: \.1) { Text($0.0).tag($0.1) }
                    }
                    .labelsHidden()
                    .frame(width: 104)
                    // Disabled while activate()/move are in flight: setIdleTime
                    // shares the lastError channel, and a failure reported while
                    // activate() is suspended would be silently wiped by its
                    // success-path refresh().
                    .disabled(activation.busy || activation.moving)
                    .accessibilityLabel(Text("Start after"))
                    .help("How long the Mac must be idle before the screen saver starts")
                }
            }

            // Gate on stateLoaded: idleTimeSeconds starts at 0 before refresh()
            // reads the real value, and the warning must not flash at launch.
            if activation.stateLoaded && activation.idleTimeSeconds == 0 {
                Label("The screen saver won't start automatically while set to “Never”.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            DisclosureGroup {
                Text(String(localized: "lockScreenExplanation", defaultValue: """
                Lumitext shows your text while the Mac is idle, in the same window every \
                screensaver uses. Once macOS fully locks the screen, the system login \
                window takes over and no third-party app can draw there — that's an OS \
                security boundary. For the longest visible time, set “require password” \
                to begin a little after the screensaver starts.
                """))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.s1)
            } label: {
                Label {
                    Text("Why text disappears at the lock screen")
                        .font(.system(size: 12))
                } icon: {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if let err = activation.lastError {
                VStack(alignment: .leading, spacing: Theme.s1) {
                    Label {
                        // Errors are self-contained, localized sentences set at the
                        // source (ActivationManager) — no hardcoded prefix, which
                        // used to mislabel e.g. a move failure as a set failure.
                        // Text(verbatim:) keeps the runtime string out of the
                        // LocalizedStringKey format machinery (err may contain '%').
                        Text(verbatim: err)
                            .font(.caption)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption)
                    }
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    // The manual fallback when programmatic activation can't
                    // complete (PLAN.md's documented deep-link escape hatch):
                    // let the user finish the job in System Settings directly.
                    Button("Open Screen Saver Settings…") {
                        activation.openScreenSaverSettings()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onAppear {
                    AccessibilityNotification.Announcement(err).post()
                }
                // One error replacing another in place (A → B without passing
                // through nil) reuses this view, so .onAppear won't refire —
                // announce the new text too, or VoiceOver users hear only the
                // stale first error.
                .onChange(of: err) { _, newErr in
                    AccessibilityNotification.Announcement(newErr).post()
                }
            }
        }
        .animation(reduceMotion ? nil : Theme.selectAnim, value: activation.lastError)
        .animation(reduceMotion ? nil : Theme.selectAnim, value: activation.stateLoaded && activation.idleTimeSeconds == 0)
    }

    /// The window's primary action: Return-triggerable, shows progress while the
    /// pluginkit+PaperSaver run is in flight, and confirms success inline.
    private var activateButton: some View {
        Button {
            Task {
                await activation.activate()
                guard activation.isActiveSaver, activation.lastError == nil else { return }
                withAnimation(reduceMotion ? nil : Theme.selectAnim) { justActivated = true }
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(reduceMotion ? nil : Theme.selectAnim) { justActivated = false }
            }
        } label: {
            if activation.busy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Setting…")
                }
            } else if justActivated && activation.isActiveSaver {
                // && isActiveSaver: if the user deactivates the saver externally
                // (System Settings) inside the 2.5s confirmation window, the
                // green checkmark must not keep contradicting the status dot.
                Label("Screen saver set", systemImage: "checkmark.circle.fill")
            } else {
                Label("Set as Screen Saver", systemImage: "sparkles.tv")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(justActivated && activation.isActiveSaver ? Theme.ok : Theme.accent)
        .keyboardShortcut(.defaultAction)
        // Also disabled during the green confirmation window — a second click
        // there would race a second activate() Task against the reset sleep.
        // And outside /Applications: registering from a wrong path wedges pkd's
        // single-path election (the moveNotice above explains what to do).
        .disabled(activation.busy || activation.moving || justActivated || !activation.isInApplicationsFolder)
        .help("Make Lumitext the screen saver on all displays")
    }

    private var moveNotice: some View {
        WarningCard(symbol: "exclamationmark.triangle.fill") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Move Lumitext to Applications")
                    .font(.system(size: 12, weight: .semibold))
                Text("macOS only reliably finds the screensaver when the app runs from /Applications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await activation.moveToApplications() }
            } label: {
                if activation.moving {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Moving…")
                    }
                } else {
                    Text("Move…")
                }
            }
            .disabled(activation.moving || activation.busy)
        }
    }
}
