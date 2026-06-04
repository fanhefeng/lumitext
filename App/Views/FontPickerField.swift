//
//  FontPickerField.swift
//  Lumitext
//
//  Searchable font picker: the trigger shows the current family rendered in its
//  own face; the popover offers instant filtering and per-row live previews —
//  usable at 200+ installed families (a flat Picker is not).
//

import SwiftUI

struct FontPickerField: View {
    @Binding var family: String
    let families: [String]

    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker.toggle()
        } label: {
            HStack(spacing: Theme.s2) {
                displayName
                    .font(previewFont(for: family, size: 13))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, 6)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .help(displayName)
        .accessibilityLabel(Text("Family"))
        .accessibilityValue(displayName)
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            FontPickerList(family: $family, families: families, dismiss: { showPicker = false })
        }
    }

    private var displayName: Text {
        family.isEmpty ? Text("System") : Text(verbatim: family)
    }
}

private struct FontPickerList: View {
    @Binding var family: String
    let families: [String]
    let dismiss: () -> Void

    @State private var query = ""

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return families }
        return families.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.s2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search fonts", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(Theme.s3)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered, id: \.self) { name in
                        row(name)
                    }
                    if filtered.isEmpty {
                        Text("No fonts match")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(Theme.s4)
                    }
                }
            }
        }
        .frame(width: 300, height: 380)
    }

    private func row(_ name: String) -> some View {
        FontRow(name: name, selected: name == family) {
            family = name
            dismiss()
        }
    }
}

/// One popover row with its own hover highlight (LazyVStack rows need per-row
/// state; a shared style can't tint a row whose resting background is clear).
private struct FontRow: View {
    let name: String
    let selected: Bool
    let choose: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: choose) {
            HStack {
                (name.isEmpty ? Text("System") : Text(verbatim: name))
                    .font(previewFont(for: name, size: 14))
                    .lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(selected ? Theme.accent.opacity(0.14) : (hovering ? Color.white.opacity(0.06) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(name.isEmpty ? Text("System") : Text(verbatim: name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Render a name in its own face (system font for the "" sentinel). Falls back to
/// the system font when a family fails to resolve.
func previewFont(for family: String, size: CGFloat) -> Font {
    family.isEmpty ? .system(size: size) : .custom(family, size: size)
}
