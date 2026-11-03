import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The emote wheel and the library that feeds it. The library holds the built-ins and whatever
/// the user dropped in, and an import can be renamed, re-arted, given a sound or deleted — all of
/// it from this one page, without the wheel's own drag maths changing shape.
struct EmoteWheelPane: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var engine: PingFlowEngine
    @EnvironmentObject private var audio: AudioEngine
    @EnvironmentObject private var permissions: PermissionManager
    @EnvironmentObject private var library: EmoteLibrary
    @EnvironmentObject private var imports: EmoteImportQueue

    /// The wheel's own diameter, and a stage 80 pt roomier so the spoke labels are never clipped.
    private var editorSize: CGFloat { 380 }
    private var stageSize: CGFloat { editorSize + 80 }

    @State private var selectedSlice: Int? = 0
    @State private var drag: Drag?
    @State private var hoveredSlice: Int?
    @State private var hoveredEntry: String?
    @State private var dropActive = false
    @State private var notice: String?
    @State private var reduceMotion = SettingsRootView.isReduceMotion
    /// `PINGFLOW_EMOTE_FILTER` opens the pane on one category. The render harness uses it to
    /// photograph the imports, which sit at the bottom of a list it cannot scroll.
    @State private var selectedCategory: EmoteCategory? =
        EmoteCategory(rawValue: ProcessInfo.processInfo.environment["PINGFLOW_EMOTE_FILTER"] ?? "")
    @State private var query = ""
    @State private var editing: Editing?
    @State private var space = DragSpace()

    private struct Drag: Equatable {
        let key: EmoteKey
        var location: CGPoint
    }

    /// Which import the editor sheet is open on, kept as an id so the sheet always reads the
    /// library's current copy rather than a snapshot taken when it opened.
    private struct Editing: Identifiable {
        let id: String
    }

    private var slots: [EmoteKey] { store.settings.emoteWheelSlots }
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
        .sheet(item: $editing) { target in
            EmoteEditorSheet(id: target.id, onDelete: { delete(id: target.id) })
        }
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
                return "SWAP → \(library.name(for: slots[target]))"
            }
            if isOverHub { return "SET CENTRE" }
            return "DROP ON A SLICE"
        }
        if let hoveredSlice, slots.indices.contains(hoveredSlice) {
            return library.name(for: slots[hoveredSlice])
        }
        if let selectedSlice, slots.indices.contains(selectedSlice) {
            return library.name(for: slots[selectedSlice])
        }
        return "EMOTE"
    }

    // MARK: - The library

    private var libraryCard: some View {
        SectionCard("Emote library", highlightID: "emoteLibrary",
                    trailing: AnyView(ValuePlate("\(filtered.count) of \(library.entries.count)"))) {
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 10)

            ChipWrap(spacing: 4, lineSpacing: 4) {
                categoryChip(nil, label: "All")
                ForEach(EmoteCategory.allCases) { category in
                    categoryChip(category, label: category.displayName)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            dropZone
                .padding(.horizontal, 12)
                .padding(.top, 10)

            CappedScroll(cap: 300) { grid }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 12)

            statusStrip
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)
            TextField("Search emotes", text: $query)
                .textFieldStyle(.plain)
                .font(Metrics.control)
                .foregroundStyle(Palette.primaryText)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: Metrics.insetCorner, style: .continuous))
    }

    /// The import target: drop art here, or browse for it. One drop can make thirty emotes.
    private var dropZone: some View {
        let isTargeted = dropActive
        return HStack(spacing: 8) {
            Image(systemName: isTargeted ? "square.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 13))
                .foregroundStyle(isTargeted ? Palette.accent : Palette.tertiaryText)
            VStack(alignment: .leading, spacing: 1) {
                Text(isTargeted ? "Release to import" : "Drop art here")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isTargeted ? Palette.accent : Palette.secondaryText)
                    .lineLimit(1)
                Text("GIF · image · video")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button {
                browseForArt()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Choose one or many files to import.")
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(isTargeted ? Palette.accentWash : Palette.inset,
                    in: RoundedRectangle(cornerRadius: Metrics.insetCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.insetCorner, style: .continuous)
                .strokeBorder(isTargeted ? Palette.accent : Palette.hairline,
                              style: StrokeStyle(lineWidth: 1, dash: isTargeted ? [] : [3, 3]))
        )
        .animation(.easeOut(duration: 0.14), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $dropActive) { providers in
            readArt(from: providers)
        }
    }

    /// Import progress and the library's own complaints, in the one place a user looks after a drop.
    @ViewBuilder private var statusStrip: some View {
        let text = imports.notice?.text ?? library.fileIssue
        if !imports.pending.isEmpty || text != nil {
            HStack(spacing: 8) {
                if !imports.pending.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                    Text(imports.pending.count == 1
                         ? "Importing \(imports.pending[0].name)…"
                         : "Importing \(imports.pending.count) files…")
                        .font(Metrics.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
                if imports.pending.isEmpty, let text {
                    Circle()
                        .fill(imports.notice?.isError == true ? Palette.danger : Palette.success)
                        .frame(width: 5, height: 5)
                    Text(text)
                        .font(Metrics.caption)
                        .foregroundStyle(imports.notice?.isError == true ? Palette.danger : Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.rowPadding)
            .frame(minHeight: 30)
            .overlay(alignment: .top) { Hairline() }
            .transition(.opacity)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 62, maximum: 84), spacing: 7)], spacing: 7) {
            ForEach(filtered) { entry in
                EmoteLibraryCell(entry: entry,
                                 asset: library.asset(for: entry.key),
                                 slice: slots.firstIndex(of: entry.key),
                                 isHovered: hoveredEntry == entry.id,
                                 isDragged: drag?.key == entry.key,
                                 isImporting: imports.pending.contains { $0.id == entry.id },
                                 reduceMotion: reduceMotion,
                                 onHover: { hoveredEntry = $0 ? entry.id : nil },
                                 onTap: { play(entry) },
                                 onDrag: { beginDrag(entry.key) },
                                 onEnd: { finishDrag() },
                                 onEdit: { editing = Editing(id: entry.id) },
                                 onDelete: { delete(id: entry.id) })
            }
        }
        .padding(.vertical, 2)
        .overlay {
            if filtered.isEmpty { emptyState }
        }
    }

    private var emptyState: some View {
        Group {
            if !query.isEmpty {
                Text("No emote is called “\(query)”.")
            } else if selectedCategory == .custom {
                Text("Nothing imported yet.\nDrop a file above.")
                    .multilineTextAlignment(.center)
            } else {
                Text("Nothing matches this filter.")
            }
        }
        .font(Metrics.caption)
        .foregroundStyle(Palette.tertiaryText)
        .frame(maxWidth: .infinity, minHeight: 90)
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

    private var filtered: [EmoteEntry] {
        library.entries.filter { entry in
            (selectedCategory == nil || entry.category == selectedCategory)
                && (query.isEmpty || entry.name.localizedCaseInsensitiveContains(query))
        }
    }

    // MARK: - Trigger

    private var triggerCard: some View {
        SectionCard("Trigger") {
            LineRow("Hold key", highlightID: "emoteTrigger") {
                ModifierKeyPicker(selection: store.binding(\.emoteTrigger),
                                  exclude: store.settings.activationKey)
            }
            LineRow("Centre emote",
                    icon: AnyView(EmoteChip(key: store.settings.emoteClick, side: Metrics.chipSize)),
                    divider: true,
                    highlightID: "emoteClick") {
                HStack(spacing: 8) {
                    Button {
                        playCenter()
                    } label: {
                        Image(systemName: "play.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Hear \(library.name(for: store.settings.emoteClick))")
                    PillMenu(library.entries, selection: hubBinding) { option in
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

    /// The hub menu lists the library by entry, but stores the key the entry stands for.
    private var hubBinding: Binding<EmoteEntry> {
        Binding {
            let key = store.settings.emoteClick
            return library.entries.first { $0.key == key } ?? library.entries[0]
        } set: { newValue in
            store.update { $0.emoteClick = newValue.key }
        }
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
            EmoteChip(key: drag.key, side: 36)
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

    private func beginDrag(_ key: EmoteKey) {
        drag = Drag(key: key, location: space.cursorInPane() ?? .zero)
    }

    private func play(_ entry: EmoteEntry) {
        guard let asset = library.asset(for: entry.key) else {
            say("That emote's files are gone.")
            return
        }
        if !audio.playEmote(asset) {
            say(asset.soundURL == nil ? "\(asset.name) has no sound." : "\(asset.name) could not be played.")
        }
    }

    private func playCenter() {
        guard let asset = library.asset(for: store.settings.emoteClick) else { return }
        _ = audio.playEmote(asset)
    }

    private func finishDrag() {
        guard let drag else { return }
        defer { self.drag = nil }
        if isOverHub {
            store.update { $0.emoteClick = drag.key }
            say("\(library.name(for: drag.key)) now sits in the centre.")
            tick()
            return
        }
        guard let slice = dropTarget else {
            say("Dropped outside the wheel — nothing changed.")
            return
        }
        apply(drag.key, to: slice)
    }

    private func apply(_ key: EmoteKey, to slice: Int) {
        guard slots.indices.contains(slice) else { return }
        guard let next = EmoteWheelEditor.place(slots, emote: key, at: slice) else { return }
        store.update { $0.emoteWheelSlots = next }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.76)) { selectedSlice = slice }
        tick()
        say("\(library.name(for: key)) → slice \(slice) (\(compass(slice))).")
    }

    private func restoreDefault() {
        store.update { $0.emoteWheelSlots = EmoteDefinition.defaultWheel }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { selectedSlice = 0 }
        tick()
        say("Default arrangement restored.")
    }

    /// Takes an import out of the library and off the wheel, so no slice is left pointing at a
    /// folder that no longer exists.
    private func delete(id: String) {
        guard let emote = library.importedEmote(id) else { return }
        if editing?.id == id { editing = nil }
        let key = library.remove(id)
        store.update {
            $0.emoteWheelSlots = EmoteWheelEditor.evict($0.emoteWheelSlots, key)
            if $0.emoteClick == key { $0.emoteClick = .shipped(.cheeky_poro) }
        }
        withAnimation(.easeOut(duration: 0.18)) { hoveredEntry = nil }
        say("\(emote.name) deleted.")
        Log.input.info("Emote \(emote.name, privacy: .public) deleted")
    }

    private func browseForArt() {
        imports.add(artURLs: Self.pickFiles(contentTypes: [.image, .movie, .video], multiple: true))
    }

    /// Reads dropped file URLs. A single provider is read per file, so a thirty-file drop still
    /// lands every name, in whatever order the pasteboard hands them over.
    private func readArt(from providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { self.imports.add(artURLs: [url]) }
            }
        }
        return true
    }

    static func pickFiles(contentTypes: [UTType], multiple: Bool) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = contentTypes
        panel.prompt = multiple ? "Import" : "Choose"
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
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

// MARK: - Library cell

/// One emote in the grid. Hovering it plays its art — a gif or a clip runs, everything else stays
/// a still — so a library of imports can be skimmed without importing a decoder per cell.
private struct EmoteLibraryCell: View {
    let entry: EmoteEntry
    let asset: EmoteAsset?
    let slice: Int?
    let isHovered: Bool
    let isDragged: Bool
    let isImporting: Bool
    let reduceMotion: Bool
    var onHover: (Bool) -> Void
    var onTap: () -> Void
    var onDrag: () -> Void
    var onEnd: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                art
                if let slice {
                    Text("\(slice)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 14, height: 14)
                        .background(Palette.accent, in: Circle())
                        .offset(x: 9, y: -7)
                }
            }
            Text(entry.name)
                .font(.system(size: 9.5, weight: isHovered ? .semibold : .medium))
                .foregroundStyle(isHovered ? Palette.primaryText : Palette.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
            kindBadge
                .frame(height: 11)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .padding(.horizontal, 3)
        .background(fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .opacity(isDragged || isImporting ? 0.35 : 1)
        .scaleEffect(isHovered && !isDragged && !isImporting ? 1.04 : 1)
        .overlay(alignment: .bottom) { if isImporting { ProgressView().controlSize(.mini).padding(.bottom, 3) } }
        .overlay(alignment: .topLeading) { hoverToolbar }
        .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isHovered)
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.16), value: isHovered)
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.12), value: isDragged)
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onTapGesture(perform: onTap)
        .gesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .local)
                .onChanged { _ in onDrag() }
                .onEnded { _ in onEnd() }
        )
        .help("Drag onto a slice · click to hear it")
        .accessibilityLabel("\(entry.name) emote\(slice.map { ", on slice \($0)" } ?? "")")
    }

    @ViewBuilder private var art: some View {
        if let asset {
            EmoteArtView(asset: asset, animates: isHovered, corner: 17)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
        } else {
            Circle()
                .fill(Palette.plate)
                .frame(width: 34, height: 34)
                .overlay(
                    Text(String(entry.name.prefix(1)).uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.secondaryText)
                )
                .accessibilityHidden(true)
        }
    }

    private var kindBadge: some View {
        HStack(spacing: 3) {
            Text(entry.kindLabel)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.tertiaryText)
            if entry.hasSound {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Palette.success)
            }
        }
    }

    /// The two things you can do to an import, shown only while its cell is hovered.
    @ViewBuilder private var hoverToolbar: some View {
        if isHovered && entry.isImported && !isImporting {
            HStack(spacing: 3) {
                miniButton("pencil", label: "Edit", action: onEdit)
                miniButton("trash", label: "Delete", tint: Palette.danger, action: onDelete)
            }
            .padding(3)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .offset(x: 3, y: 3)
            .transition(.opacity)
        }
    }

    private func miniButton(_ symbol: String, label: String, tint: Color = Palette.chipInk,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16, height: 16)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private var fill: Color {
        if isHovered { return Palette.chipBackground }
        return Palette.inset
    }
}

/// A still chip for a slot: the drag ghost and the centre row both need one small, unmoving image.
private struct EmoteChip: View {
    let key: EmoteKey
    var side: CGFloat = 24

    var body: some View {
        Group {
            if let image = EmoteLibrary.shared.poster(for: key) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(hex: "#4a4e54"))
                    .overlay(
                        Text(String(EmoteLibrary.shared.name(for: key).prefix(1)).uppercased())
                            .font(.system(size: side * 0.4, weight: .bold))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

// MARK: - Import editor

/// The sheet an import opens: its name, its art, its sound. Art and sound each take a drop from
/// Finder or a trip through the open panel; nothing is converted, so a file leaves as it arrived.
private struct EmoteEditorSheet: View {
    let id: String
    let onDelete: () -> Void

    @EnvironmentObject private var library: EmoteLibrary
    @EnvironmentObject private var imports: EmoteImportQueue
    @EnvironmentObject private var audio: AudioEngine
    @Environment(\.dismiss) private var dismiss

    @State private var nameDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            artRow
            soundRow
            footer
        }
        .padding(20)
        .frame(width: 432)
        .background(Palette.windowBackground)
        .onAppear { nameDraft = library.importedEmote(id)?.name ?? "" }
    }

    private var emote: CustomEmote? { library.importedEmote(id) }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            preview
            VStack(alignment: .leading, spacing: 5) {
                Text("EMOTE")
                    .font(Metrics.eyebrow)
                    .tracking(1.1)
                    .foregroundStyle(Palette.tertiaryText)
                TextField("Name", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                    .onSubmit { library.rename(id, to: nameDraft) }
                    .onChange(of: nameDraft) { next in library.rename(id, to: next) }
                if let emote {
                    Text("From \(emote.originName) · \(emote.media.byteLabel)")
                        .font(Metrics.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder private var preview: some View {
        if let emote, let asset = library.asset(for: emote.key) {
            EmoteArtView(asset: asset, animates: true, corner: 10)
                .frame(width: 84, height: 84)
                .background(Palette.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Palette.inset)
                .frame(width: 84, height: 84)
                .overlay(Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Palette.warning))
        }
    }

    private var artRow: some View {
        ImportDropRow(title: "Art",
                      detail: artDetail,
                      symbol: "photo",
                      contentTypes: [.image, .movie, .video],
                      onPick: { url in imports.replaceArt(of: id, with: url) })
    }

    private var soundRow: some View {
        ImportDropRow(title: "Sound",
                      detail: soundDetail,
                      symbol: "waveform",
                      contentTypes: [.audio],
                      trailing: sound == nil ? nil : AnyView(soundTrailing),
                      onPick: { url in imports.replaceSound(of: id, with: url) })
    }

    private var artDetail: String {
        guard let media = emote?.media else { return "Its files are gone." }
        var parts = [media.kindLabel, "\(media.width)×\(media.height)"]
        if media.frameCount > 1 { parts.append("\(media.frameCount) frames") }
        if media.duration > 0 { parts.append(media.durationLabel) }
        return parts.joined(separator: " · ")
    }

    private var sound: EmoteSound? { emote?.sound }

    private var soundDetail: String {
        guard let sound else { return "Silent — drop an audio file to give it a voice." }
        return "\(sound.formatLabel) · \(sound.durationLabel) · \(sound.byteLabel)"
    }

    private var soundTrailing: some View {
        HStack(spacing: 7) {
            Button {
                if let emote, let asset = library.asset(for: emote.key) { _ = audio.playEmote(asset) }
            } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Hear it")
            Button("Remove") { imports.replaceSound(of: id, with: nil) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Leave this emote silent.")
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Delete emote", role: .destructive) { onDelete() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Palette.danger)
            Spacer()
            if let note = imports.notice {
                Text(note.text)
                    .font(Metrics.caption)
                    .foregroundStyle(note.isError ? Palette.danger : Palette.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// One importable half of an emote: a plate that takes a file from Finder or from the open panel.
/// Both rows share the plate's look, so the sheet reads as two of the same thing rather than two
/// one-off controls.
private struct ImportDropRow: View {
    let title: String
    let detail: String
    let symbol: String
    let contentTypes: [UTType]
    var trailing: AnyView? = nil
    let onPick: (URL) -> Void

    @State private var targeted = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(Palette.chipInk)
                .frame(width: 22, height: 22)
                .background(Palette.chipBackground,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Metrics.rowTitle)
                    .foregroundStyle(Palette.primaryText)
                Text(detail)
                    .font(Metrics.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let trailing { trailing }
            Button("Choose…") {
                if let url = EmoteWheelPane.pickFiles(contentTypes: contentTypes, multiple: false).first {
                    onPick(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(targeted ? Palette.accentWash : Palette.inset,
                    in: RoundedRectangle(cornerRadius: Metrics.insetCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.insetCorner, style: .continuous)
                .strokeBorder(targeted ? Palette.accent : Palette.hairline,
                              style: StrokeStyle(lineWidth: 1, dash: targeted ? [] : [3, 3]))
        )
        .animation(.easeOut(duration: 0.14), value: targeted)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in readOne(from: providers) }
    }

    /// A row takes exactly one file; anything else in the drop is ignored rather than guessed at.
    private func readOne(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async { self.onPick(url) }
        }
        return true
    }
}
