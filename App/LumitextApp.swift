//
//  LumitextApp.swift
//  Lumitext
//
//  M1 spike host: carries the saver appex and shows where it lives.
//  The real config GUI arrives in M4.
//

import SwiftUI

@main
struct LumitextApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Text("Lumitext")
                    .font(.largeTitle.bold())
                Text("M1 spike host — screensaver appex carrier")
                    .foregroundStyle(.secondary)
                if let path = Bundle.main.builtInPlugInsURL?
                    .appendingPathComponent("LumitextSaver.appex").path {
                    Text(path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            .padding(40)
            .frame(minWidth: 560)
        }
    }
}
