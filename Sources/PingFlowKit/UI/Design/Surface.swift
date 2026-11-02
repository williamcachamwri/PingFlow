import AppKit
import SwiftUI

/// The surfaces a settings page is built from. One rule holds the whole set together: a card is a
/// single fill with no stroke, and anything inside it is separated by a hairline, never by another
/// panel. Colour is reserved for the things you can act on.

// MARK: - Hairline

/// The only rule the interface draws.
struct Hairline: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

// MARK: - Page header

/// The line that says where you are: a title, one line of what the page is for, and the values the
/// page is currently holding. It sits above the scroll view, so it never leaves.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var trailing: Trailing

    init(_ title: String, subtitle: String? = nil,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Metrics.pageHeader)
                        .foregroundStyle(Palette.primaryText)
                    if let subtitle {
                        Text(subtitle)
                            .font(Metrics.pageSubtitle)
                            .foregroundStyle(Palette.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.bottom, 10)
            Hairline()
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Section card

/// One card, one job. The header strip is optional and only used when a page has more than one
/// group; a card of its own needs no label to explain itself.
struct SectionCard<Content: View>: View {
    @EnvironmentObject private var router: SettingsRouter
    var eyebrow: String? = nil
    var highlightID: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    init(_ eyebrow: String? = nil, highlightID: String? = nil, trailing: AnyView? = nil,
         @ViewBuilder content: () -> Content) {
        self.eyebrow = eyebrow
        self.highlightID = highlightID
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let eyebrow { headerStrip(eyebrow) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.cardBackground,
                    in: RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                .strokeBorder(highlighted ? Palette.accent : .clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous))
        .animation(.easeOut(duration: 0.3), value: router.highlight)
        .accessibilityElement(children: .contain)
    }

    private var highlighted: Bool {
        highlightID != nil && highlightID == router.highlight
    }

    private func headerStrip(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(text.uppercased())
                .font(Metrics.eyebrow)
                .tracking(1.1)
                .foregroundStyle(Palette.tertiaryText)
            Spacer(minLength: 10)
            trailing
        }
        .padding(.horizontal, Metrics.rowPadding)
        .frame(height: 34)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

// MARK: - Line

/// A row that lives inside a card: no fill of its own, a hairline when it is not the first.
struct LineRow<Control: View>: View {
    @EnvironmentObject private var router: SettingsRouter
    let title: String
    var subtitle: String? = nil
    var icon: AnyView? = nil
    var divider = false
    var highlightID: String? = nil
    var action: (() -> Void)? = nil
    var control: Control

    @State private var hovering = false

    init(_ title: String, subtitle: String? = nil, icon: AnyView? = nil, divider: Bool = false,
         highlightID: String? = nil, action: (() -> Void)? = nil,
         @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.divider = divider
        self.highlightID = highlightID
        self.action = action
        self.control = control()
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { row }.buttonStyle(.plain)
            } else {
                row
            }
        }
        .background(hovering ? Palette.cardHover : Color.clear)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.3), value: router.highlight)
        .overlay(alignment: .top) { if divider { Hairline() } }
        .overlay(alignment: .leading) {
            if highlighted {
                Rectangle().fill(Palette.accent).frame(width: 2)
            }
        }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }

    private var highlighted: Bool {
        highlightID != nil && highlightID == router.highlight
    }

    private var row: some View {
        HStack(alignment: .center, spacing: 12) {
            if let icon { icon }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Metrics.rowTitle)
                    .foregroundStyle(Palette.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(Metrics.rowSubtitle)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control
                .fixedSize()
        }
        .padding(.horizontal, Metrics.rowPadding)
        .frame(minHeight: Metrics.lineHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension LineRow where Control == EmptyView {
    init(_ title: String, subtitle: String? = nil, icon: AnyView? = nil, divider: Bool = false,
         highlightID: String? = nil, action: (() -> Void)? = nil) {
        self.init(title, subtitle: subtitle, icon: icon, divider: divider,
                  highlightID: highlightID, action: action) { EmptyView() }
    }
}

// MARK: - Plates

/// A value, in the column every other value on the page lines up with.
struct ValuePlate: View {
    enum Tone { case neutral, accent, success, warning, danger }

    let text: String
    var tone: Tone = .neutral
    var width: CGFloat? = nil

    init(_ text: String, tone: Tone = .neutral, width: CGFloat? = nil) {
        self.text = text
        self.tone = tone
        self.width = width
    }

    var body: some View {
        Text(text)
            .font(Metrics.mono)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(minWidth: width, alignment: .trailing)
            .background(Palette.plate, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel(text)
    }

    private var color: Color {
        switch tone {
        case .neutral: return Palette.secondaryText
        case .accent: return Palette.accent
        case .success: return Palette.success
        case .warning: return Palette.warning
        case .danger: return Palette.danger
        }
    }
}

/// A key, drawn the way the keyboard draws it.
struct KeyCap: View {
    let symbol: String
    var side: CGFloat = 26
    var isOn = false

    init(_ symbol: String, side: CGFloat = 26, isOn: Bool = false) {
        self.symbol = symbol
        self.side = side
        self.isOn = isOn
    }

    var body: some View {
        Text(symbol)
            .font(.system(size: side * 0.52, weight: .medium))
            .foregroundStyle(isOn ? Palette.onAccent : Palette.chipInk)
            .frame(width: side, height: side)
            .background(isOn ? Palette.accent : Palette.controlBackground,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isOn ? Color.clear : Palette.controlBorder, lineWidth: 1)
            )
            .accessibilityLabel(symbol)
    }
}

// MARK: - Slider

/// A rail, a filled portion and a knob. The knob is the only part that moves, so it is the only
/// part that gets any weight.
struct RailSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var trackWidth: CGFloat = 168
    var label: String = ""
    var onCommit: (() -> Void)? = nil

    @State private var hovering = false
    @State private var pressing = false

    private let knob: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let usable = max(1, width - knob)
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let centre = fraction * usable + knob / 2

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.inset)
                    .frame(width: width, height: 4)
                Capsule()
                    .fill(Palette.accent.opacity(pressing ? 1 : 0.85))
                    .frame(width: max(4, centre), height: 4)
                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .overlay(Circle().strokeBorder(Palette.controlBorder, lineWidth: 1))
                    .shadow(color: Palette.cardShadow, radius: hovering ? 2.5 : 1.5, x: 0, y: 0.75)
                    .offset(x: centre - knob / 2)
                    .scaleEffect(pressing ? 1.14 : (hovering ? 1.06 : 1))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in commit(to: drag.location.x, across: usable) }
                    .onEnded { _ in
                        pressing = false
                        onCommit?()
                    }
            )
            .onTapGesture { }
        }
        .frame(width: trackWidth, height: 22)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.1), value: pressing)
        .onHover { hovering = $0 }
        .accessibilityElement()
        .accessibilityLabel(label.isEmpty ? "Value" : label)
        .accessibilityValue(Text(readout))
        .accessibilityAction(named: "Increase") { nudge(1) }
        .accessibilityAction(named: "Decrease") { nudge(-1) }
    }

    private func commit(to x: CGFloat, across usable: CGFloat) {
        pressing = true
        let fraction = min(max(0, (x - knob / 2) / usable), 1)
        var next = range.lowerBound + Double(fraction) * (range.upperBound - range.lowerBound)
        if let step { next = (next / step).rounded() * step }
        value = min(max(next, range.lowerBound), range.upperBound)
    }

    private func nudge(_ direction: Int) {
        let size = step ?? (range.upperBound - range.lowerBound) / 20
        value = min(max(value + Double(direction) * size, range.lowerBound), range.upperBound)
    }

    private var readout: String {
        if let step, step >= 1 { return String(format: "%.0f", value) }
        return String(format: "%.2f", value)
    }
}

/// A slider with its value in the plate column: the row's whole right edge is one object.
struct MeasuredSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var trackWidth: CGFloat = 168
    var plateWidth: CGFloat = 56
    var label: String = ""
    var readout: (Double) -> String
    var onCommit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            RailSlider(value: $value, range: range, step: step, trackWidth: trackWidth,
                       label: label, onCommit: onCommit)
            ValuePlate(readout(value), width: plateWidth)
        }
    }
}

// MARK: - Segmented

/// Small set of choices, all visible at once — no click to discover what the menu was holding.
struct Segmented<Option: Hashable & Identifiable, Label: View>: View {
    let options: [Option]
    @Binding var selection: Option
    var onPick: ((Option) -> Void)? = nil
    /// A segmented control on the page sits in a control well, not in a card well.
    var track: Color = Palette.inset
    var thumb: Color = Palette.raised
    let label: (Option) -> Label

    @Namespace private var segment
    @State private var hovered: Option?

    init(_ options: [Option], selection: Binding<Option>, track: Color = Palette.inset,
         thumb: Color = Palette.raised,
         onPick: ((Option) -> Void)? = nil, @ViewBuilder label: @escaping (Option) -> Label) {
        self.options = options
        self._selection = selection
        self.track = track
        self.thumb = thumb
        self.onPick = onPick
        self.label = label
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button {
                    selection = option
                    onPick?(option)
                } label: {
                    label(option)
                        .font(Metrics.caption)
                        .foregroundStyle(isChosen(option) ? Palette.primaryText : Palette.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(background(for: option))
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? option : nil }
                .accessibilityAddTraits(isChosen(option) ? .isSelected : [])
            }
        }
        .padding(2)
        .background(track, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: selection)
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private func isChosen(_ option: Option) -> Bool { option == selection }

    @ViewBuilder private func background(for option: Option) -> some View {
        if isChosen(option) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(thumb)
                .shadow(color: Palette.cardShadow, radius: 1.5, x: 0, y: 1)
                .matchedGeometryEffect(id: "segment", in: segment)
        } else if hovered == option {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.controlHover.opacity(0.5))
        }
    }
}

/// The mark on a row that goes somewhere rather than toggles something.
struct GoMark: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.tertiaryText)
            .accessibilityHidden(true)
    }
}

// MARK: - Flow

/// Chips that drop onto a second line when the column is narrow, so a filter never
/// has to clip a word to fit.
struct ChipWrap: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let limit = proposal.width ?? .infinity
        let lines = flow(limit: limit, subviews: subviews)
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, lines.count - 1))
        let width = lines.map(\.width).max() ?? 0
        return CGSize(width: Swift.min(limit, width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY
        for line in flow(limit: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private func flow(limit: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let added = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if added > limit && !current.indices.isEmpty {
                lines.append(current)
                current = Line()
            }
            let start = current.indices.isEmpty ? 0 : current.width + spacing
            current.width = start + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { lines.append(current) }
        return lines
    }
}

// MARK: - Swatches

/// The wheel's own colour, chosen by looking at it rather than at a word for it.
struct SwatchPicker<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    var onPick: ((Option) -> Void)? = nil
    let color: (Option) -> Color
    let name: (Option) -> String

    @State private var hovered: Option?

    init(_ options: [Option], selection: Binding<Option>,
         onPick: ((Option) -> Void)? = nil,
         color: @escaping (Option) -> Color, name: @escaping (Option) -> String) {
        self.options = options
        self._selection = selection
        self.onPick = onPick
        self.color = color
        self.name = name
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(options) { option in
                Button {
                    selection = option
                    onPick?(option)
                } label: {
                    Circle()
                        .fill(color(option))
                        .frame(width: 13, height: 13)
                        .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 0.75))
                        .scaleEffect(hovered == option ? 1.18 : 1)
                        .padding(3.5)
                        .overlay {
                            if selection == option {
                                Circle().strokeBorder(Palette.primaryText, lineWidth: 1.5)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(name(option))
                .onHover { hovered = $0 ? option : nil }
                .accessibilityLabel(name(option))
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.8), value: hovered)
        .animation(.spring(response: 0.26, dampingFraction: 0.8), value: selection)
    }
}
