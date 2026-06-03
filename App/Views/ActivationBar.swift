//
//  ActivationBar.swift
//  Lumitext
//
//  Install/activation controls + the honest "lock screen" explanation and the
//  idle-time helper. Lives under the preview on the right side of the window.
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
        VStack(alignment: .leading, spacing: 12) {
            if !activation.isInApplicationsFolder {
                GroupBox {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Move Lumitext to Applications").font(.subheadline.bold())
                            Text("macOS only reliably finds the screensaver when the app runs from /Applications.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Move…") { activation.moveToApplications() }
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    activation.registerExtension()
                    Task { await activation.setAsScreensaverEverywhere() }
                } label: {
                    Label("Set as Screen Saver", systemImage: "sparkles.tv")
                }
                .buttonStyle(.borderedProminent)
                .disabled(activation.busy)

                if activation.isActiveSaver {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Not active").foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack {
                Text("Start after").foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { activation.idleTimeSeconds },
                    set: { activation.setIdleTime($0) }
                )) {
                    ForEach(idleChoices, id: \.1) { Text($0.0).tag($0.1) }
                }
                .labelsHidden()
                .frame(width: 120)
                Spacer()
            }

            DisclosureGroup("About “lock screen”") {
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
                .padding(.top, 4)
            }
            .font(.subheadline)

            if let err = activation.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
