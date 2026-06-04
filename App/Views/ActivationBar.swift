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
                Button {
                    Task {
                        await activation.registerExtension()
                        await activation.setAsScreensaverEverywhere()
                    }
                } label: {
                    Label("Set as Screen Saver", systemImage: "sparkles.tv")
                }
                .buttonStyle(.borderedProminent)
                .disabled(activation.busy)

                HStack(spacing: 6) {
                    Circle()
                        .fill(activation.isActiveSaver ? Theme.ok : Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text(activation.isActiveSaver ? "Active" : "Not active")
                        .font(.system(size: 12))
                        .foregroundStyle(activation.isActiveSaver ? Color.primary : Color.secondary)
                }

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
                }
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
                    Text("About “lock screen”")
                        .font(.system(size: 12))
                } icon: {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if let err = activation.lastError {
                Label {
                    Text(err).font(.caption)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption)
                }
                .foregroundStyle(.red)
            }
        }
    }

    private var moveNotice: some View {
        HStack(spacing: Theme.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
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
        .padding(Theme.s3)
        .background(Theme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous)
                .strokeBorder(Theme.warning.opacity(0.3), lineWidth: 1)
        )
    }
}
