//
//  ColorBinding.swift
//  Lumitext
//
//  Bridges the model's Codable RGBAColor to SwiftUI's ColorPicker (Binding<Color>).
//

import SwiftUI
import AppKit
import LumitextCore

extension Binding where Value == RGBAColor {
    /// A Binding<Color> backed by an RGBAColor binding, for use with ColorPicker.
    var asColor: Binding<Color> {
        Binding<Color>(
            get: { wrappedValue.swiftUIColor },
            set: { newColor in wrappedValue = RGBAColor(NSColor(newColor)) }
        )
    }
}
