//
//  PositionGrid.swift
//  Lumitext
//
//  3×3 position picker: each cell is a miniature "screen" showing where the text
//  block would sit. Replaces the two segmented controls — one glance, one click.
//

import SwiftUI
import LumitextCore

struct PositionGrid: View {
    @Binding var horizontal: LumitextCore.HorizontalAlignment
    @Binding var vertical: LumitextCore.VerticalAlignment

    private let columns: [LumitextCore.HorizontalAlignment] = [.leading, .center, .trailing]
    private let rows: [LumitextCore.VerticalAlignment] = [.top, .center, .bottom]

    var body: some View {
        VStack(spacing: Theme.s1 + 2) {
            ForEach(rows, id: \.self) { v in
                HStack(spacing: Theme.s1 + 2) {
                    ForEach(columns, id: \.self) { h in
                        cell(h: h, v: v)
                    }
                }
            }
        }
    }

    private func cell(h: LumitextCore.HorizontalAlignment, v: LumitextCore.VerticalAlignment) -> some View {
        let selected = horizontal == h && vertical == v
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                horizontal = h
                vertical = v
            }
        } label: {
            ZStack(alignment: Alignment(horizontal: h.swiftUI, vertical: v.swiftUI)) {
                RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.85) : Theme.surfaceRaised)
                // The mini "text block".
                RoundedRectangle(cornerRadius: 2)
                    .fill(selected ? Color.white : Color.secondary.opacity(0.7))
                    .frame(width: 16, height: 5)
                    .padding(6)
            }
            .frame(width: 52, height: 34)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Theme.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11yLabel(h: h, v: v))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Localized, human-readable position name (reuses the Top/Middle/Bottom and
    /// Left/Center/Right string-table keys).
    private func a11yLabel(h: LumitextCore.HorizontalAlignment, v: LumitextCore.VerticalAlignment) -> Text {
        let vKey: LocalizedStringKey = v == .top ? "Top" : (v == .center ? "Middle" : "Bottom")
        let hKey: LocalizedStringKey = h == .leading ? "Left" : (h == .center ? "Center" : "Right")
        return Text(vKey) + Text(verbatim: " ") + Text(hKey)
    }
}
