import AppKit
import SwiftUI

struct PingWheelPane: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var engine: PingFlowEngine
    @EnvironmentObject private var audio: AudioEngine
    @EnvironmentObject private var permissions: PermissionManager
    @EnvironmentObject private var router: SettingsRouter

    /// The wheel's own diameter, and a stage 80 pt roomier so the spoke labels are never clipped.
    private var editorSize: CGFloat { 380 }
    private var stageSize: CGFloat { editorSize + 80 }

    @State private var selectedSlice: Int? = 0
    @State private var drag: Drag?
    @State private var hoveredSlice: Int?
    @State private var notice: String?
    @State private var reduceMotion = SettingsRootView.isReduceMotion
    @State private var space = DragSpace()

    private struct Drag: Equatable {
        let ping: PingDefinition.ID
        var location: CGPoint
    }

    private var slots: [PingDefinition.ID] { store.settings.wheelSlots }
    private var layout: WheelLayout { WheelLayout(size: editorSize) }

    var body: some View {
        SettingsPage {
            Workbench {
                wheelCard.staggered(0, enabled: !reduceMotion)
                libraryCard.staggered(1, enabled: !reduceMotion)
            }
            hubCard.staggered(2, enabled: !reduceMotion)
        }
        .background(SpaceMarker { space.paneView = $0 })
        .overlay(alignment: .topLeading) { dragGhost }
    }

    // MARK: - The wheel

    private var wheelCard: some View {
        SectionCard(highlightID: "wheelSlots") {
            ZStack {
                StageGlow(layout: layout)
                PingWheelView(slots: slots,
                              hoveredSlice: activeSlice,
                              size: editorSize,
                              dimUnhoveredIcons: store.settings.dimUnhoveredIcons,
                              showCentreLabel: store.settings.showCentreLabel,
                              centreText: centreLabel,
                              hubImageName: PingDefinition.definition(for: store.settings.clickPing).iconTexture,
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
                Button("Restore League's") { restoreLeague() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isLeagueArrangement)
                    .help("Put the eight stock pings back on the wheel.")
                Button {
                    engine.presentWheelAtCurrentPointer()
                } label: {
                    Label("Try it", systemImage: "cursorarrow.rays")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Palette.accent)
                .disabled(!(permissions.isGranted && store.settings.isEnabled))
                .help(canTryDetail)
            }
            .padding(.horizontal, Metrics.rowPadding)
            .frame(minHeight: 38)
        }
    }

    private var activeSlice: Int? { drag != nil ? dropTarget : (hoveredSlice ?? selectedSlice) }

    private var canTryDetail: String {
        permissions.isGranted && store.settings.isEnabled
            ? "Opens the real wheel at your pointer, at \(Int(store.settings.wheelSize)) pt."
            : "Needs Accessibility allowed and PingFlow enabled."
    }

    private var centreLabel: String {
        if drag != nil {
            if let target = dropTarget, slots.indices.contains(target) {
                return "SWAP → \(PingDefinition.definition(for: slots[target]).name)"
            }
            if isOverHub { return "SET CENTRE" }
            return "DROP ON A SLICE"
        }
        if let hoveredSlice, slots.indices.contains(hoveredSlice) {
            return PingDefinition.definition(for: slots[hoveredSlice]).name
        }
        if let selectedSlice, slots.indices.contains(selectedSlice) {
            return PingDefinition.definition(for: slots[selectedSlice]).name
        }
        return "PING"
    }

    // MARK: - The library

    private var libraryCard: some View {
        SectionCard("Ping library",
                    trailing: AnyView(ValuePlate("\(visibleLibrary.count) of \(PingDefinition.all.count)"))) {
            CappedScroll(cap: 372) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 104), spacing: 8)], spacing: 8) {
                    ForEach(visibleLibrary) { definition in
                        LibraryCell(definition: definition,
                                    slice: slots.firstIndex(of: definition.id),
                                    isSelected: selectedSlice.map { slots[$0] == definition.id } ?? false,
                                    isDragged: drag?.ping == definition.id,
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

    private var visibleLibrary: [PingDefinition] {
        PingDefinition.all.filter { router.scope.contains($0) }
    }

    // MARK: - The centre

    private var hubBinding: Binding<PingDefinition> {
        Binding(get: { PingDefinition.definition(for: store.settings.clickPing) },
                set: { newValue in store.update { $0.clickPing = newValue.id } })
    }

    private var hubCard: some View {
        SectionCard("The centre") {
            LineRow("Hub ping", icon: AnyView(PingChip(ping: hubPing)), highlightID: "clickPing") {
                HStack(spacing: 8) {
                    Button {
                        audio.play(hubPing)
                    } label: {
                        Image(systemName: "play.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Play \(hubPing.name)")
                    PillMenu(PingDefinition.all, selection: hubBinding) { option in
                        Text(option.name)
                    }
                }
            }
            LineRow("Idle icons", divider: true, highlightID: "dimUnhoveredIcons") {
                PingSwitch(isOn: store.binding(\.dimUnhoveredIcons))
            }
            .help("Off the wheel they wear League's gold; the one under the pointer shows its real colours.")
            LineRow("Name in the centre", divider: true, highlightID: "showCentreLabel") {
                PingSwitch(isOn: store.binding(\.showCentreLabel))
            }
            .help("The hovered ping's name, in League's blue.")
        }
    }

    private var hubPing: PingDefinition {
        PingDefinition.definition(for: store.settings.clickPing)
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
            let definition = PingDefinition.definition(for: drag.ping)
            PingIcon(ping: definition, side: 40)
                .padding(9)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color(hex: definition.colorHex).opacity(0.85), lineWidth: 2))
                .shadow(color: Palette.cardShadow, radius: 10, y: 4)
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

    private func beginDrag(_ ping: PingDefinition.ID) {
        drag = Drag(ping: ping, location: space.cursorInPane() ?? .zero)
    }

    private func preview(_ definition: PingDefinition) {
        audio.play(definition)
    }

    private func finishDrag() {
        guard let drag else { return }
        defer { self.drag = nil }
        if isOverHub {
            store.update { $0.clickPing = drag.ping }
            say("\(PingDefinition.definition(for: drag.ping).name) now sits in the centre.")
            tick()
            return
        }
        guard let slice = dropTarget else {
            say("Dropped outside the wheel — nothing changed.")
            return
        }
        apply(drag.ping, to: slice)
    }

    private func apply(_ ping: PingDefinition.ID, to slice: Int) {
        guard slots.indices.contains(slice) else { return }
        guard let next = WheelEditor.place(slots, ping: ping, at: slice) else { return }
        store.update { $0.wheelSlots = next }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.76)) { selectedSlice = slice }
        tick()
        let definition = PingDefinition.definition(for: ping)
        say("\(definition.name) → slice \(slice) (\(compass(slice))).")
        Log.ui.info("Wheel slice \(slice) set to \(definition.name), privacy: .public)")
    }

    private func restoreLeague() {
        store.update { $0.wheelSlots = PingDefinition.defaultWheel }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { selectedSlice = 0 }
        tick()
        say("League's arrangement restored.")
    }

    private var isLeagueArrangement: Bool { slots == PingDefinition.defaultWheel }

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

private struct LibraryCell: View {
    let definition: PingDefinition
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
                PingIcon(ping: definition, side: 34, tinted: slice == nil && !hovering)
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
        .padding(.vertical, 11)
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
        .accessibilityLabel("\(definition.name) ping\(slice.map { ", on slice \($0)" } ?? ", in the library")")
    }

    private var fill: Color {
        if isSelected { return Palette.accentWash }
        if hovering { return Palette.chipBackground }
        return Palette.inset
    }
}
