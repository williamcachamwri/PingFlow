import AppKit
import SwiftUI

struct EmoteWheelPane: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var engine: PingFlowEngine
    @EnvironmentObject private var audio: AudioEngine
    @EnvironmentObject private var permissions: PermissionManager

    /// The wheel's own diameter, and a stage 80 pt roomier so the spoke labels are never clipped.
    private var editorSize: CGFloat { 380 }
    private var stageSize: CGFloat { editorSize + 80 }

    @State private var selectedSlice: Int? = 0
    @State private var drag: Drag?
    @State private var hoveredSlice: Int?
    @State private var notice: String?
    @State private var reduceMotion = SettingsRootView.isReduceMotion
    @State private var selectedCategory: EmoteCategory? = nil
    @State private var space = DragSpace()

    private struct Drag: Equatable {
        let emote: EmoteDefinition.ID
        var location: CGPoint
    }

    private var slots: [EmoteDefinition.ID] { store.settings.emoteWheelSlots }
    private var layout: WheelLayout { WheelLayout(size: editorSize) }

    var body: some View {
        SettingsPage {
            Workbench {
                wheelCard.staggered(0, enabled: !reduceMotion)
                libraryCard.staggered(1, enabled: !reduceMotion)
            }
            triggerCard.staggered(2, enabled: !reduceMotion)
        }
        .background(SpaceMarker { space.paneView = $0 })
        .overlay(alignment: .topLeading) { dragGhost }
    }

    // MARK: - The wheel

    private var wheelCard: some View {
        SectionCard(highlightID: "emoteWheelSlots") {
            LineRow("Emote wheel", icon: AnyView(IconChip(symbol: "face.smiling")),
                    highlightID: "emoteEnabled") {
                PingSwitch(isOn: store.binding(\.emoteEnabled))
            }
            .help("Hold \(store.settings.emoteTrigger.glyph) anywhere, drag out, release over a slice.")

            Hairline()

            ZStack {
                StageGlow(layout: layout)
                EmoteWheelView(slots: slots,
                               hoveredSlice: activeSlice,
                               size: editorSize,
                               centreText: centreLabel,
                               interactive: drag == nil,
                               onHover: { hoveredSlice = $0 },
                               onPick: { select(slice: $0) })
                    .scaleEffect(drag == nil ? 1 : 0.985)
                    .animation(.easeOut(duration: reduceMotion ? 0 : 0.16), value: drag == nil)
                    .animation(.spring(response: 0.34, dampingFraction: 0.76), value: slots)
                    .frame(width: editorSize, height: editorSize)
                    .background(SpaceMarker { space.wheelView = $0 })
                StageMarks(layout: layout, selected: activeSlice, compass: compass)
            }
            .frame(width: stageSize, height: stageSize)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)

            Hairline()

            HStack(alignment: .center, spacing: 10) {
                if let notice {
                    Text(notice)
                        .font(Metrics.caption)
                        .foregroundStyle(Palette.accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
                Spacer(minLength: 8)
                Button("Restore default") { restoreDefault() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isDefaultArrangement)
                    .help("Put the stock eight emotes back on the wheel.")
                Button {
                    presentEmoteWheel()
                } label: {
                    Label("Try it", systemImage: "cursorarrow.rays")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Palette.accent)
                .disabled(!(permissions.isGranted && store.settings.isEnabled && store.settings.emoteEnabled))
                .help(canTryDetail)
            }
            .padding(.horizontal, Metrics.rowPadding)
            .frame(minHeight: 38)
        }
    }

    private var activeSlice: Int? { drag != nil ? dropTarget : (hoveredSlice ?? selectedSlice) }

    private var isDefaultArrangement: Bool { slots == EmoteDefinition.defaultWheel }

    private var canTryDetail: String {
        permissions.isGranted && store.settings.isEnabled && store.settings.emoteEnabled
            ? "Opens the real emote wheel at your pointer."
            : "Needs Accessibility allowed, PingFlow enabled and the emote wheel on."
    }

    private var centreLabel: String {
        if drag != nil {
            if let target = dropTarget, slots.indices.contains(target) {
                return "SWAP → \(EmoteDefinition.definition(for: slots[target]).name)"
            }
            if isOverHub { return "SET CENTRE" }
            return "DROP ON A SLICE"
        }
        if let hoveredSlice, slots.indices.contains(hoveredSlice) {
            return EmoteDefinition.definition(for: slots[hoveredSlice]).name
        }
        if let selectedSlice, slots.indices.contains(selectedSlice) {
            return EmoteDefinition.definition(for: slots[selectedSlice]).name
        }
        return "EMOTE"
    }

    // MARK: - The library

    private var libraryCard: some View {
        SectionCard("Emote library",
                    trailing: AnyView(ValuePlate("\(filteredEmotes.count) of \(EmoteDefinition.all.count)"))) {
            ChipWrap(spacing: 4, lineSpacing: 4) {
                categoryChip(nil, label: "All")
                ForEach(EmoteCategory.allCases) { category in
                    categoryChip(category, label: category.displayName)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 10)

            CappedScroll(cap: 320) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 8)], spacing: 8) {
                    ForEach(filteredEmotes) { definition in
                        EmoteLibraryCell(definition: definition,
                                         slice: slots.firstIndex(of: definition.id),
                                         isSelected: selectedSlice.map { slots[$0] == definition.id } ?? false,
                                         isDragged: drag?.emote == definition.id,
                                         reduceMotion: reduceMotion,
                                         onTap: { preview(definition) },
                                         onDrag: { beginDrag(definition.id) },
                                         onEnd: { finishDrag() })
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func categoryChip(_ category: EmoteCategory?, label: String) -> some View {
        let isSelected = selectedCategory == category
        return Button(label) {
            selectedCategory = category
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
        .foregroundStyle(isSelected ? Palette.primaryText : Palette.secondaryText)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(isSelected ? Palette.raised : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: isSelected ? Palette.cardShadow : .clear, radius: 1.5, x: 0, y: 1)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var filteredEmotes: [EmoteDefinition] {
        if let category = selectedCategory {
            return EmoteDefinition.all.filter { $0.category == category }
        }
        return EmoteDefinition.all
    }

    // MARK: - Trigger

    private var triggerCard: some View {
        SectionCard("Trigger") {
            LineRow("Hold key", highlightID: "emoteTrigger") {
                ModifierKeyPicker(selection: store.binding(\.emoteTrigger),
                                  exclude: store.settings.activationKey)
            }
            LineRow("Centre emote",
                    icon: AnyView(EmoteChip(emote: centreEmote, side: Metrics.chipSize)),
                    divider: true,
                    highlightID: "emoteClick") {
                HStack(spacing: 8) {
                    Button {
                        audio.playEmote(centreEmote)
                    } label: {
                        Image(systemName: "play.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Play \(centreEmote.name)")
                    PillMenu(EmoteDefinition.all, selection: hubBinding) { option in
                        Text(option.name)
                    }
                }
            }
            LineRow("Sounds", divider: true, highlightID: "emoteSoundsEnabled") {
                PingSwitch(isOn: store.binding(\.emoteSoundsEnabled))
            }
            .help("Off leaves only the wheel's tick while you aim.")
        }
    }

    private var centreEmote: EmoteDefinition {
        EmoteDefinition.definition(for: store.settings.emoteClick)
    }

    private var hubBinding: Binding<EmoteDefinition> {
        Binding(get: { EmoteDefinition.definition(for: store.settings.emoteClick) },
                set: { newValue in store.update { $0.emoteClick = newValue.id } })
    }

    // MARK: - Drop target maths

    private var cursorInWheel: CGPoint? { space.cursorInWheel() }

    private var dragRadius: CGFloat {
        guard let cursorInWheel else { return 0 }
        let c = CGPoint(x: editorSize / 2, y: editorSize / 2)
        return hypot(cursorInWheel.x - c.x, cursorInWheel.y - c.y)
    }

    private var isOverHub: Bool { drag != nil && dragRadius < layout.innerRadius }

    private var dropTarget: Int? {
        guard drag != nil, let cursorInWheel else { return nil }
        let c = CGPoint(x: editorSize / 2, y: editorSize / 2)
        let dx = cursorInWheel.x - c.x
        let dy = cursorInWheel.y - c.y
        let radius = hypot(dx, dy)
        if radius < layout.innerRadius || radius > layout.extensionRadius { return nil }
        let index = WheelGeometry.sliceIndex(dx: dx, dy: dy, deadZone: layout.innerRadius)
        return index >= 0 ? index : nil
    }

    @ViewBuilder private var dragGhost: some View {
        if let drag {
            let definition = EmoteDefinition.definition(for: drag.emote)
            EmoteChip(emote: definition, side: 36)
                .position(x: drag.location.x, y: drag.location.y - 24)
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func select(slice: Int) {
        selectedSlice = slice
        tick()
    }

    private func beginDrag(_ emote: EmoteDefinition.ID) {
        drag = Drag(emote: emote, location: space.cursorInPane() ?? .zero)
    }

    private func preview(_ definition: EmoteDefinition) {
        audio.playEmote(definition)
    }

    private func finishDrag() {
        guard let drag else { return }
        defer { self.drag = nil }
        if isOverHub {
            store.update { $0.emoteClick = drag.emote }
            say("\(EmoteDefinition.definition(for: drag.emote).name) now sits in the centre.")
            tick()
            return
        }
        guard let slice = dropTarget else {
            say("Dropped outside the wheel — nothing changed.")
            return
        }
        apply(drag.emote, to: slice)
    }

    private func apply(_ emote: EmoteDefinition.ID, to slice: Int) {
        guard slots.indices.contains(slice) else { return }
        guard let next = EmoteWheelEditor.place(slots, emote: emote, at: slice) else { return }
        store.update { $0.emoteWheelSlots = next }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.76)) { selectedSlice = slice }
        tick()
        let definition = EmoteDefinition.definition(for: emote)
        say("\(definition.name) → slice \(slice) (\(compass(slice))).")
    }

    private func restoreDefault() {
        store.update { $0.emoteWheelSlots = EmoteDefinition.defaultWheel }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { selectedSlice = 0 }
        tick()
        say("Default arrangement restored.")
    }

    private func presentEmoteWheel() {
        let point = CoordinateSpace.cgPoint(fromAppKit: NSEvent.mouseLocation)
        overlay.presentEmoteWheel(at: point)
        emoteScene.open(at: point, settings: store.settings)
    }

    private var overlay: OverlayController { engine.overlay }
    private var emoteScene: EmoteScene { engine.emoteScene }

    private func compass(_ slice: Int) -> String {
        ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][slice % 8]
    }

    private func tick() {
        guard store.settings.tickSoundEnabled else { return }
        audio.play(soundName: PingDefinition.tickSound, level: store.settings.tickVolume)
    }

    private func say(_ text: String) {
        notice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            if notice == text { withAnimation(.easeOut(duration: 0.2)) { notice = nil } }
        }
    }
}

private struct EmoteChip: View {
    let emote: EmoteDefinition
    var side: CGFloat = 24

    var body: some View {
        Group {
            if let image = AssetCatalog.shared.emoteImage(named: emote.textureName) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(hex: "#4a4e54"))
                    .overlay(
                        Text(String(emote.name.prefix(1)).uppercased())
                            .font(.system(size: side * 0.4, weight: .bold))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

private struct EmoteLibraryCell: View {
    let definition: EmoteDefinition
    let slice: Int?
    let isSelected: Bool
    let isDragged: Bool
    let reduceMotion: Bool
    var onTap: () -> Void
    var onDrag: () -> Void
    var onEnd: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                EmoteChip(emote: definition, side: 34)
                if let slice {
                    Text("\(slice)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 14, height: 14)
                        .background(Palette.accent, in: Circle())
                        .offset(x: 10, y: -8)
                }
            }
            Text(definition.name)
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Palette.primaryText : Palette.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .opacity(isDragged ? 0.3 : 1)
        .scaleEffect(hovering && !isDragged ? 1.03 : 1)
        .animation(.spring(response: 0.26, dampingFraction: 0.78), value: hovering)
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.16), value: isSelected)
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.12), value: isDragged)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
        .gesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .local)
                .onChanged { _ in onDrag() }
                .onEnded { _ in onEnd() }
        )
        .help("Drag onto a slice · click to hear it")
        .accessibilityLabel("\(definition.name) emote\(slice.map { ", on slice \($0)" } ?? "")")
    }

    private var fill: Color {
        if isSelected { return Palette.accentWash }
        if hovering { return Palette.chipBackground }
        return Palette.inset
    }
}
