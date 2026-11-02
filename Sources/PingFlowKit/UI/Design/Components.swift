import SwiftUI

/// Clean checkbox.
struct RayCheck: View {
    enum State { case on, off, indeterminate }
    let state: State
    var onChange: ((Bool) -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        Button {
            onChange?(state != .on)
        } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(state == .on ? Palette.accent : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(hovering ? Palette.secondaryText : Palette.controlBorder, lineWidth: 1)
                )
                .overlay(glyph)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.15), value: state == .on)
        .modifier(AccessibilityToggleTrait())
        .accessibilityLabel("Enabled")
        .accessibilityValue(state == .on ? "on" : (state == .off ? "off" : "mixed"))
    }

    @ViewBuilder private var glyph: some View {
        switch state {
        case .on:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        case .indeterminate:
            Capsule().fill(Palette.secondaryText).frame(width: 8, height: 1.5)
        case .off:
            EmptyView()
        }
    }
}

/// Modern switch. Clean, minimal.
struct PingSwitch: View {
    @Binding var isOn: Bool
    var enabledColor: Color = Palette.accent
    var onChange: ((Bool) -> Void)? = nil

    @State private var pressing = false

    var body: some View {
        Button {
            isOn.toggle()
            onChange?(isOn)
        } label: {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isOn ? enabledColor : Palette.chipBackground)
                    .frame(width: 36, height: 20)
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0.5)
                    .offset(x: isOn ? 18 : 2)
                    .scaleEffect(pressing ? 0.9 : 1)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isOn)
            .animation(.easeOut(duration: 0.1), value: pressing)
        }
        .buttonStyle(.plain)
        .modifier(AccessibilityToggleTrait())
        .accessibilityValue(isOn ? "on" : "off")
    }
}

struct AccessibilityToggleTrait: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.accessibilityAddTraits(.isToggle)
        } else {
            content
        }
    }
}

/// Clean pill menu.
struct PillMenu<Option: Hashable & Identifiable, Label: View>: View {
    let options: [Option]
    @Binding var selection: Option
    var label: (Option) -> Label
    var prompt: String? = nil
    var onPick: ((Option) -> Void)? = nil
    var width: CGFloat? = nil

    @State private var open = false

    init(_ options: [Option], selection: Binding<Option>, prompt: String? = nil,
         width: CGFloat? = nil, onPick: ((Option) -> Void)? = nil,
         label: @escaping (Option) -> Label) {
        self.options = options
        self._selection = selection
        self.prompt = prompt
        self.width = width
        self.onPick = onPick
        self.label = label
    }

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(options) { option in
                    label(option).tag(option)
                }
            } label: { EmptyView() }
        } label: {
            HStack(spacing: 6) {
                if let prompt { Text(prompt).foregroundStyle(Palette.secondaryText) }
                label(selection)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryText)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .font(Metrics.control)
            .foregroundStyle(Palette.primaryText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .frame(width: width)
            .background(Palette.controlBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .simultaneousGesture(TapGesture().onEnded { })
        .onChange(of: selection) { newValue in onPick?(newValue) }
    }
}

/// Status dot.
struct StatusDot: View {
    enum Kind { case live, idle, blocked }
    let kind: Kind
    @State private var pulse = false

    private var color: Color {
        switch kind {
        case .live: return Palette.success
        case .idle: return Palette.tertiaryText
        case .blocked: return Palette.danger
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .strokeBorder(color.opacity(0.4), lineWidth: 2)
                    .scaleEffect(kind == .live ? 1.8 : 1)
                    .opacity(kind == .live && pulse ? 0 : 0.8)
            )
            .onAppear {
                guard kind == .live else { return }
                withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) { pulse = true }
            }
            .onChange(of: kind) { next in
                pulse = false
                guard next == .live else { return }
                withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) { pulse = true }
            }
    }
}

/// Staggered entrance.
struct Staggered: ViewModifier {
    let index: Int
    let enabled: Bool

    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 4)
            .onAppear {
                let delay = enabled ? Double(index) * 0.02 : 0
                withAnimation(.easeOut(duration: 0.22).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func staggered(_ index: Int, enabled: Bool = true) -> some View {
        modifier(Staggered(index: index, enabled: enabled))
    }
}

/// Icon chip.
struct IconChip: View {
    let symbol: String
    var tint: Color = Palette.chipInk
    var size: CGFloat = Metrics.chipSize
    var corner: CGFloat = Metrics.chipCorner

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Palette.chipBackground,
                        in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Ping chip.
struct PingChip: View {
    let ping: PingDefinition
    var size: CGFloat = Metrics.chipSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.chipCorner, style: .continuous)
                .fill(Color(hex: ping.colorHex).opacity(0.15))
            if let image = AssetCatalog.shared.image(named: ping.iconTexture) {
                Image(nsImage: PingIcon.sized(image, to: size * 0.7))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * 0.7, height: size * 0.7)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Ping icon.
struct PingIcon: View {
    let ping: PingDefinition
    var side: CGFloat = 24
    var tinted = false

    var body: some View {
        Group {
            if let image = AssetCatalog.shared.image(named: ping.iconTexture) {
                Image(nsImage: Self.sized(tinted ? TintedIconCache.tinted(image, key: ping.iconTexture) : image,
                                          to: side))
                    .resizable()
                    .interpolation(.high)
            } else {
                Circle()
                    .fill(Color(hex: ping.colorHex).opacity(0.85))
                    .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    static func sized(_ image: NSImage, to side: CGFloat) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: side, height: side)
        return copy
    }
}

/// Note card. The one card that carries a message instead of a setting.
struct NoteCard: View {
    let text: String
    var tone: InlineTone = .info

    init(_ text: String, tone: InlineTone = .info) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: tone.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tone.color)
                .padding(.top, 1)
            Text(text)
                .font(Metrics.rowSubtitle)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.rowPadding)
        .frame(minHeight: Metrics.rowHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.cardBackground,
                    in: RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Inline note for search results.
struct InlineNote: View {
    enum Tone { case info, danger }
    let text: String
    var tone: Tone = .info

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: tone == .danger ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(tone == .danger ? Palette.danger : Palette.tertiaryText)
                .padding(.top, 2)
            Text(text)
                .font(Metrics.caption)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}

enum InlineTone {
    case info, warning, danger

    var color: Color {
        switch self {
        case .info: return Palette.tertiaryText
        case .warning: return Palette.warning
        case .danger: return Palette.danger
        }
    }

    var symbol: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "exclamationmark.circle.fill"
        }
    }
}
