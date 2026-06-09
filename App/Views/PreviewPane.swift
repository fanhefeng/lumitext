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

    /// Mirror the aspect ratio of the display the saver will actually run on.
    /// The renderer scales typography by height, so the vertical look is always
    /// faithful — but TEXT WRAPS AT THE CONTAINER'S RIGHT EDGE, so only a
    /// matching aspect ratio makes horizontal fit/wrapping WYSIWYG too (a fixed
    /// 16:10 frame mispredicts wrapping on 16:9 and ultrawide screens).
    @State private var screenAspect: CGFloat = PreviewPane.mainScreenAspect()
    /// The saver runs per-screen at EACH display's own aspect; the preview can
    /// only mirror one. When attached displays disagree, say so instead of
    /// letting the wrap prediction silently over-promise.
    @State private var hasMixedAspects: Bool = PreviewPane.screensDisagreeOnAspect()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            Text("Preview")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            // Screen. No .animation(value:) here — preset/position mutations are
            // already wrapped in withAnimation at the source, and diffing the
            // whole config would re-evaluate on every keystroke.
            //
            // The aspect ratio is applied to the RENDER REGION itself, with the
            // bezel as a non-consuming background around it. Insetting a
            // fixed-aspect frame instead (the old structure) skews the region's
            // aspect — (W-14)/(H-14) ≠ W/H — and text wrapping happens at the
            // region's right edge, so even a ~1.5% skew makes the preview
            // mispredict the saver's wrap points.
            LumitextTextView(config: config)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rScreen, style: .continuous))
                .overlay {
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
                .aspectRatio(screenAspect, contentMode: .fit)
                .padding(7)
                .background {
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
                }
                .shadow(color: config.backgroundColor.swiftUIColor.opacity(0.45), radius: 26, y: 10)
            // Fill whatever height the right column offers; the aspect-fit screen
            // centers inside, so a taller window means a bigger preview instead
            // of dead space.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification)) { _ in
                screenAspect = Self.mainScreenAspect()
                hasMixedAspects = Self.screensDisagreeOnAspect()
            }
            // didChangeScreenParameters does NOT fire when the window is merely
            // dragged between two already-attached displays — without this the
            // preview keeps the previous display's aspect (stale wrap points).
            .onReceive(NotificationCenter.default.publisher(
                for: NSWindow.didChangeScreenNotification)) { note in
                guard let window = note.object as? NSWindow,
                      window.isVisible,
                      let screen = window.screen,
                      let a = Self.aspect(of: screen) else { return }
                screenAspect = a
                hasMixedAspects = Self.screensDisagreeOnAspect()
            }
            // The preview repeats the editor's text — exposing the whole SwiftUI
            // subtree to VoiceOver duplicates every word in the swipe order.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Preview"))

            if hasMixedAspects {
                Label("Preview matches the main display; text may wrap differently on your other displays",
                      systemImage: "display.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A screen's width:height ratio, or nil for a degenerate (zero-height) frame.
    /// One definition so the params-changed, window-moved, and mixed-aspect paths
    /// can't drift apart (e.g. if this ever has to account for notch insets).
    private static func aspect(of screen: NSScreen) -> CGFloat? {
        screen.frame.height > 0 ? screen.frame.width / screen.frame.height : nil
    }

    /// Aspect of the screen the saver is most likely to run on (the main screen);
    /// falls back to 16:10 (the built-in display ratio) when unavailable.
    private static func mainScreenAspect() -> CGFloat {
        guard let screen = NSScreen.main, let a = aspect(of: screen) else { return 16.0 / 10.0 }
        return a
    }

    /// True when attached displays have meaningfully different aspect ratios
    /// (beyond ~1%), i.e. the single-aspect preview can't be faithful to all.
    private static func screensDisagreeOnAspect() -> Bool {
        let aspects = NSScreen.screens.compactMap(aspect(of:))
        guard let first = aspects.first else { return false }
        return aspects.contains { abs($0 - first) > 0.01 }
    }
}
