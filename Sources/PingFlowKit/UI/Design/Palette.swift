import AppKit
import SwiftUI

/// Every colour the interface uses, defined once as a dynamic NSColor so light and dark are the
/// same code path. The ladder is deliberate: sidebar is the deepest layer, the page sits above it,
/// a card sits above the page and an inset sits below everything. Nothing separates those layers
/// with a stroke — depth comes from fill alone, which is why light mode has a grey page rather
/// than a white one.
enum Palette {
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        })
    }

    private static func hex(_ string: String, _ alpha: CGFloat = 1) -> NSColor {
        var text = string
        if text.hasPrefix("#") { text.removeFirst() }
        let value = UInt64(text, radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255,
                       alpha: alpha)
    }

    /// Two hex strings, one per mode.
    private static func pair(_ light: String, _ dark: String, _ alpha: CGFloat = 1) -> Color {
        dynamic(light: hex(light, alpha), dark: hex(dark, alpha))
    }

    // MARK: Layers

    static var sidebarBackground: Color { pair("#EDEDEA", "#1A1A1A") }
    static var windowBackground: Color { pair("#F6F6F4", "#131313") }
    static var cardBackground: Color { pair("#FFFFFF", "#212121") }
    static var cardHover: Color { pair("#F7F7F5", "#292929") }
    /// The well a control or an inset plate sits in — always a step below the card it lives on.
    static var inset: Color { pair("#F1F1EE", "#1A1A1A") }
    static var plate: Color { pair("#EFEFEC", "#2B2B2B") }
    /// The thumb of a segmented control: always a step above whatever track it sits on.
    static var raised: Color { pair("#FFFFFF", "#3D3D3D") }

    // MARK: Lines and text

    /// The only rule the interface draws: between rows inside one card, and under a header.
    static var hairline: Color { pair("#E7E7E3", "#313131") }
    static var sidebarDivider: Color { pair("#E3E3E0", "#262626") }
    static var primaryText: Color { pair("#141414", "#EDEDED") }
    static var secondaryText: Color { pair("#67676D", "#9C9C9C") }
    static var tertiaryText: Color { pair("#9B9BA1", "#6B6B6B") }

    // MARK: Controls

    static var controlBackground: Color { pair("#F1F1EE", "#2E2E2E") }
    static var controlBorder: Color { pair("#D8D8D4", "#4A4A4A") }
    static var controlHover: Color { pair("#EAEAE7", "#353535") }
    static var rowHover: Color { cardHover }
    /// The square behind a sidebar glyph — one step above the sidebar, never the card colour.
    static var chipBackground: Color { pair("#E4E4E1", "#333333") }
    static var chipInk: Color { pair("#5A5A5E", "#CFCFCF") }
    /// The sidebar's chosen row.
    static var selection: Color { pair("#E4E4E2", "#2E2E2E") }

    // MARK: Colour

    /// The only hue the interface keeps: blue, and only on things you can act on.
    static var accent: Color { pair("#3B82F6", "#60A5FA") }
    static var onAccent: Color { pair("#FFFFFF", "#FFFFFF") }
    static var accentWash: Color { pair("#3B82F6", "#60A5FA", 0.14) }
    static var success: Color { pair("#1FA35C", "#3FD27C") }
    static var warning: Color { pair("#B7791F", "#EAB308") }
    static var danger: Color { pair("#D6402C", "#FF5C4D") }
    /// A checkbox's own ink: ticks are drawn in near-white, never in an accent.
    static var checkmark: Color { pair("#2C2C2E", "#F2F2F2") }
    static var cardShadow: Color { pair("#1C1C1E", "#000000", 0.06) }
}

/// The type and spacing scale: tight, consistent, modern.
enum Metrics {
    static let pagePadding: CGFloat = 20
    static let sectionGap: CGFloat = 16
    static let groupGap: CGFloat = 20
    static let cardCorner: CGFloat = 12
    static let insetCorner: CGFloat = 8
    static let rowHeight: CGFloat = 48
    static let lineHeight: CGFloat = 44
    static let rowPadding: CGFloat = 16
    static let sidebarWidth: CGFloat = 232
    static let contentMaxWidth: CGFloat = 760
    static let chipSize: CGFloat = 26
    static let chipCorner: CGFloat = 7
    static let navRowHeight: CGFloat = 34
    static let toolbarHeight: CGFloat = 34

    static let pageHeader = Font.system(size: 17, weight: .semibold)
    static let pageSubtitle = Font.system(size: 12, weight: .regular)
    static let eyebrow = Font.system(size: 9, weight: .semibold, design: .monospaced)
    static let mono = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let rowTitle = Font.system(size: 13.5, weight: .regular)
    static let rowSubtitle = Font.system(size: 12, weight: .regular)
    static let sidebarSection = Font.system(size: 11, weight: .semibold)
    static let sidebarItem = Font.system(size: 13.5, weight: .regular)
    static let control = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 11, weight: .regular)
}

extension NSColor {
    /// The hex strings in the ping table and the accent swatches, in one place.
    convenience init(hex: String) {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        let value = UInt64(text, radix: 16) ?? 0
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}
