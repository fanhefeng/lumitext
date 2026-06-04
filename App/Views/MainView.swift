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
                Spacer(minLength: 0)
                if let warn = model.persistenceWarning {
                    Label(warn, systemImage: "externaldrive.badge.xmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(Theme.s5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(red: 0.055, green: 0.07, blue: 0.13))
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .frame(minWidth: 880, minHeight: 640)
    }
}
