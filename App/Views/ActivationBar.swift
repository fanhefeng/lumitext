//
//  ActivationBar.swift
//  Lumitext
//
//  Install/activation controls + the honest "lock screen" explanation and the
//  idle-time helper, restyled as a section card with a clear status dot.
//

import SwiftUI
import LumitextCore

struct ActivationBar: View {
    @ObservedObject var activation: ActivationManager

    /// Transient post-success confirmation on the button itself.
    @State private var justActivated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let idleChoices: [(LocalizedStringKey, Int)] = [
        ("1 min", 60), ("2 min", 120), ("5 min", 300),
        ("10 min", 600), ("20 min", 1200), ("Never", 0),
    ]

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

                Spacer(minLength: 0)

                HStack(spacing: Theme.s2) {
                    Text("Start after")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { activation.idleTimeSeconds },
                        set: { activation.setIdleTime($0) }
                    )) {
                        ForEach(idleChoices, id: \.1) { Text($0.0).tag($0.1) }
                    }
                    .labelsHidden()
                    .frame(width: 104)
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
                Label {
                    // Text(verbatim:) keeps the runtime error string out of the
                    // LocalizedStringKey format machinery (err may contain '%').
                    Text("\(Text("Couldn't set the screen saver.")) \(Text(verbatim: err))")
                        .font(.caption)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption)
                }
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .move(edge: .top)))
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
            } else if justActivated {
                Label("Screen saver set", systemImage: "checkmark.circle.fill")
            } else {
                Label("Set as Screen Saver", systemImage: "sparkles.tv")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(justActivated ? Theme.ok : Theme.accent)
        .keyboardShortcut(.defaultAction)
        // Also disabled during the green confirmation window — a second click
        // there would race a second activate() Task against the reset sleep.
        .disabled(activation.busy || justActivated)
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
            Button("Move…") { activation.moveToApplications() }
        }
    }
}
