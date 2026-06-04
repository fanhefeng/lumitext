//
//  PreviewPane.swift
//  Lumitext
//
//  Live WYSIWYG preview presented as a display: dark bezel, screen glass, soft
//  glow shadow. Embeds the SAME LumitextTextView the screensaver uses; the
//  renderer scales typography by container height, so this small preview is a
//  faithful miniature of the full-screen result. Config changes crossfade.
//

import SwiftUI
import LumitextCore

struct PreviewPane: View {
    let config: LumitextConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            Text("Preview")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            ZStack {
                // Bezel
                RoundedRectangle(cornerRadius: Theme.rScreen + 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.16), Color(white: 0.05)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.rScreen + 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )

                // Screen. No .animation(value:) here — preset/position mutations are
                // already wrapped in withAnimation at the source, and diffing the
                // whole config would re-evaluate on every keystroke.
                LumitextTextView(config: config)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rScreen, style: .continuous))
                    .padding(7)

                // A blank screen explains itself; tint adapts to the backdrop.
                if config.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("Your text will appear here", systemImage: "text.cursor")
                        .font(.callout)
                        .foregroundStyle(
                            (config.backgroundColor.isLight ? Color.black : Color.white).opacity(0.5)
                        )
                        .allowsHitTesting(false)
                }
            }
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .shadow(color: config.backgroundColor.swiftUIColor.opacity(0.45), radius: 26, y: 10)
            // Fill whatever height the right column offers; the aspect-fit screen
            // centers inside, so a taller window means a bigger preview instead
            // of dead space.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
