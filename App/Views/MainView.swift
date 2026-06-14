//
//  MainView.swift
//  Lumitext
//
//  Apple Music-style layout via the native NavigationSplitView: the editing
//  controls live in a translucent Liquid Glass SIDEBAR (the system supplies the
//  floating-panel material and the window's glass chrome), and the live preview +
//  activation sit in a solid detail pane. This is the Apple-recommended way to get
//  the sidebar look — no custom window-background glass hacks.
//

import SwiftUI

struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var activation: ActivationManager

    var body: some View {
        NavigationSplitView {
            ConfigPanel(config: $model.config, fontFamilies: model.fontFamilies)
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
        } detail: {
            VStack(alignment: .leading, spacing: Theme.s4) {
                PreviewPane(config: model.config)
                ActivationBar(activation: activation)
                if let warn = model.persistenceWarning {
                    persistenceBanner(warn)
                }
            }
            .padding(Theme.s5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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
