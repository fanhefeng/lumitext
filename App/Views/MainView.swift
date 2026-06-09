//
//  MainView.swift
//  Lumitext
//
//  The window layout: editing controls on the left, live preview + activation on
//  the right, on a unified night background. Dark appearance is forced — a
//  screensaver configurator is a dark-room tool, and the design language
//  (night indigo, hairlines at white-8%) is tuned for it.
//

import SwiftUI
import LumitextCore

struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var activation: ActivationManager

    var body: some View {
        HStack(spacing: 0) {
            ConfigPanel(config: $model.config, fontFamilies: model.fontFamilies)
                .frame(width: 380)

            Divider().overlay(Theme.hairline)

            VStack(alignment: .leading, spacing: Theme.s4) {
                PreviewPane(config: model.config)
                Divider().overlay(Theme.hairline)
                ActivationBar(activation: activation)
                if let warn = model.persistenceWarning {
                    persistenceBanner(warn)
                }
            }
            .padding(Theme.s5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.windowBackground)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .navigationTitle("Lumitext")
        .frame(minWidth: 880, minHeight: 720)
    }

    /// "Changes won't reach the screensaver" is an alarm, not a footnote — same
    /// warning treatment as the move-to-Applications notice.
    private func persistenceBanner(_ message: String) -> some View {
        WarningCard(symbol: "externaldrive.badge.xmark") {
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
