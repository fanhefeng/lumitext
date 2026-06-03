//
//  MainView.swift
//  Lumitext
//
//  The window layout: editing controls on the left, live preview + activation on
//  the right. Takes plain observed objects so it can be rendered headlessly for
//  snapshot verification (see LumitextApp's snapshot hook).
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

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                PreviewPane(config: model.config)
                Divider()
                ActivationBar(activation: activation)
                Spacer(minLength: 0)
                if let warn = model.persistenceWarning {
                    Label(warn, systemImage: "externaldrive.badge.xmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.background)
        }
        .frame(minWidth: 880, minHeight: 620)
    }
}
