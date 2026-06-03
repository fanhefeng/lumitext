//
//  PreviewPane.swift
//  Lumitext
//
//  Live WYSIWYG preview. Embeds the SAME LumitextTextView the screensaver uses, in
//  a 16:10 "display" frame. Because the renderer scales typography by container
//  height, this small preview is a faithful miniature of the full-screen result.
//

import SwiftUI
import LumitextCore

struct PreviewPane: View {
    let config: LumitextConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.headline)
                .foregroundStyle(.secondary)

            LumitextTextView(config: config)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                .frame(maxWidth: .infinity)
        }
    }
}
