import AppKit
import SwiftUI

/// The window's content: a status plate and a grouped index on the left, and on the right a single
/// toolbar, a header that names the page and shows what it currently holds, then the page itself
/// in a column that stops at a readable width instead of running to the glass.
struct SettingsRootView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var router: SettingsRouter
    @EnvironmentObject private var permissions: PermissionManager
    @EnvironmentObject private var engine: PingFlowEngine

    @Namespace private var selectionNamespace
    @State private var reduceMotion = SettingsRootView.isReduceMotion
    /// Bumped every time the page changes. Used as the detail's identity so the staggered
    /// entrance plays for the new pane instead of being skipped by view reuse.
    @State private var appearIndex = 0

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Metrics.sidebarWidth)
                .background(Palette.sidebarBackground)
            Rectangle()
                .fill(Palette.sidebarDivider)
                .frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.windowBackground)
        }
        .frame(minWidth: 1000, minHeight: 620)
        .background(Palette.windowBackground)
        .ignoresSafeArea()
        .onChange(of: router.destination) { _ in
            appearIndex += 1
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusPlate()
                .padding(.horizontal, 14)
                .padding(.top, 40)
                .padding(.bottom, 16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(NavGroup.allCases) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title.uppercased())
                                .font(Metrics.eyebrow)
                                .tracking(1.1)
                                .foregroundStyle(Palette.tertiaryText)
                                .padding(.leading, 10)
                                .padding(.bottom, 3)
                            ForEach(group.panes) { pane in
                                NavRow(pane: pane, namespace: selectionNamespace,
                                       index: SettingsPane.allCases.firstIndex(of: pane) ?? 0)
                                    .staggered(SettingsPane.allCases.firstIndex(of: pane) ?? 0,
                                               enabled: !reduceMotion)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 16)
            }

            SidebarFooter()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                ToolbarRow()
                PageHeader(router.destination.title, subtitle: router.destination.subtitle) {
                    HeaderStats()
                }
            }
            .pageColumn()
            .padding(.top, 12)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: Metrics.groupGap) {
                    if isSearching {
                        SearchResults()
                    } else {
                        pageContent
                    }
                    Color.clear.frame(height: 24)
                }
                .pageColumn()
                .id(appearIndex)
                .padding(.top, 10)
            }
        }
    }

    @ViewBuilder private var pageContent: some View {
        switch router.destination {
        case .pane(let pane): pane.view
        case .ping(let id): PingDetailPane(pingID: id)
        }
    }

    private var isSearching: Bool {
        !router.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Everything in the detail column shares one measure, centred in the window.
extension View {
    func pageColumn() -> some View {
        frame(maxWidth: Metrics.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Metrics.pagePadding)
    }
}

// MARK: - Sidebar pieces

private enum NavGroup: String, CaseIterable, Identifiable {
    case preferences = "Preferences"
    case content = "Wheel"
    case system = "System"

    var id: String { rawValue }
    var title: String { rawValue }

    var panes: [SettingsPane] {
        switch self {
        case .preferences: return [.general, .interaction]
        case .content: return [.pingWheel, .emoteWheel, .sounds, .appearance]
        case .system: return [.permissions, .about]
        }
    }
}

/// The truth of the moment in 34 points: whether the wheel is live under the key, and which key.
private struct StatusPlate: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var permissions: PermissionManager
    @EnvironmentObject private var engine: PingFlowEngine

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            logo
            VStack(alignment: .leading, spacing: 2) {
                Text("PingFlow")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                HStack(spacing: 5) {
                    StatusDot(kind: dotKind).frame(width: 7)
                    Text(stateLine)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
            }
            Spacer(minLength: 6)
            KeyCap(store.settings.activationKey.glyph, side: 22)
        }
        .padding(8)
        .background(hovering ? Palette.selection.opacity(0.6) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { store.update { $0.isEnabled.toggle() } }
        .help("Click to \(store.settings.isEnabled ? "pause" : "resume") the wheel")
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var logo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.chipBackground)
            if let image = AssetCatalog.shared.image(named: PingDefinition.logoTexture) {
                Image(nsImage: SettingsRootView.sized(image, to: 20))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "smallcircle.filled.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
        .frame(width: 34, height: 34)
        .opacity(store.settings.isEnabled ? 1 : 0.55)
        .animation(.easeOut(duration: 0.18), value: store.settings.isEnabled)
    }

    private var dotKind: StatusDot.Kind {
        if !store.settings.isEnabled { return .idle }
        if !permissions.isGranted { return .blocked }
        return engine.isWheelActive ? .live : .idle
    }

    private var stateLine: String {
        guard store.settings.isEnabled else { return "Paused" }
        guard permissions.isGranted else { return "Needs access" }
        return engine.isWheelActive ? "Wheel open" : "Ready"
    }
}

/// One sidebar line: chip, label, and the pill while it is chosen.
private struct NavRow: View {
    let pane: SettingsPane
    let namespace: Namespace.ID
    let index: Int

    @EnvironmentObject private var router: SettingsRouter
    @EnvironmentObject private var permissions: PermissionManager
    @State private var hovering = false

    private var isSelected: Bool { router.destination == .pane(pane) }

    var body: some View {
        Button { router.go(.pane(pane)) } label: {
            HStack(spacing: 9) {
                chip
                Text(pane.title)
                    .font(Metrics.sidebarItem)
                    .foregroundStyle(isSelected ? Palette.primaryText : Palette.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if pane == .permissions, !permissions.isGranted {
                    Circle().fill(Palette.danger).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: Metrics.navRowHeight)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(background)
            .overlay(alignment: .leading) { rail }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var chip: some View {
        IconChip(symbol: pane.symbol, tint: isSelected ? Palette.accent : Palette.chipInk)
    }

    @ViewBuilder private var background: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.selection)
                .matchedGeometryEffect(id: "sidebar-selection", in: namespace)
        } else if hovering {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.selection.opacity(0.45))
        }
    }

    @ViewBuilder private var rail: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Palette.accent)
                .frame(width: 2.5, height: 16)
                .offset(x: -2)
                .matchedGeometryEffect(id: "sidebar-rail", in: namespace)
        }
    }
}

/// The two numbers that tell you whether this build can do anything: its version and its canvas.
private struct SidebarFooter: View {
    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack {
                Text("v\(AppInfo.version)")
                    .font(Metrics.eyebrow)
                    .tracking(0.6)
                    .foregroundStyle(Palette.tertiaryText)
                Spacer()
                let count = NSScreen.screens.count
                Text("\(count) display\(count == 1 ? "" : "s")")
                    .font(Metrics.eyebrow)
                    .tracking(0.6)
                    .foregroundStyle(Palette.tertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Toolbar

/// One row for navigation, search and the window's own look.
private struct ToolbarRow: View {
    @EnvironmentObject private var router: SettingsRouter
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        HStack(spacing: 10) {
            NavCluster()
            SearchField()
            Segmented(AppearanceMode.allCases, selection: store.binding(\.appearanceMode),
                      track: Palette.controlBackground, thumb: Palette.raised) { mode in
                Image(systemName: mode.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 20, height: 14)
                    .help(mode.displayName)
            }
        }
    }
}

private struct NavCluster: View {
    @EnvironmentObject private var router: SettingsRouter

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", enabled: router.canGoBack, action: router.back,
                  keys: "[", help: "Back (⌘[)")
            Rectangle().fill(Palette.hairline).frame(width: 1, height: 14)
            arrow("chevron.right", enabled: router.canGoForward, action: router.forward,
                  keys: "]", help: "Forward (⌘])")
        }
        .background(Palette.controlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void,
                       keys: Character, help: String) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? Palette.primaryText : Palette.tertiaryText)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .keyboardShortcut(KeyEquivalent(keys), modifiers: .command)
        .help(help)
    }
}

private struct SearchField: View {
    @EnvironmentObject private var router: SettingsRouter
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Palette.secondaryText)
            TextField("Search settings and pings", text: $router.query)
                .textFieldStyle(.plain)
                .font(Metrics.control)
                .foregroundStyle(Palette.primaryText)
                .focused($focused)
                .accessibilityLabel("Search settings")
            if router.query.isEmpty {
                Text("⌘K")
                    .font(Metrics.eyebrow)
                    .foregroundStyle(Palette.tertiaryText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Palette.plate, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Button { router.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(Palette.controlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(focused ? Palette.accent.opacity(0.8) : Color.clear, lineWidth: 1.5)
        )
        .animation(.easeOut(duration: 0.15), value: focused)
        .background(
            Button("") { focused = true }
                .keyboardShortcut("k", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        )
        .onExitCommand { if !router.query.isEmpty { router.query = "" } }
    }
}

// MARK: - Header stats

/// What the page is currently holding, in the same plate language as the rows below it.
private struct HeaderStats: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var router: SettingsRouter
    @EnvironmentObject private var permissions: PermissionManager
    @EnvironmentObject private var engine: PingFlowEngine

    var body: some View {
        plates
            .animation(.easeOut(duration: 0.2), value: router.destination)
    }

    @ViewBuilder private var plates: some View {
        HStack(spacing: 6) {
            switch router.destination {
            case .pane(.general):
                ValuePlate(stateWord, tone: stateTone)
            case .pane(.interaction):
                ValuePlate("\(store.settings.wheelSlots.count)/8 slices")
                ValuePlate("\(Int(store.settings.dragThreshold)) pt")
            case .pane(.pingWheel):
                ValuePlate("\(store.settings.wheelSlots.count)/8", tone: .accent)
                ValuePlate(isLeagueWheel ? "League" : "Custom", tone: isLeagueWheel ? .neutral : .warning)
            case .pane(.emoteWheel):
                ValuePlate("\(store.settings.emoteWheelSlots.count)/8", tone: .accent)
                ValuePlate("\(engine.library.entries.count) emotes")
            case .pane(.sounds):
                ValuePlate(store.settings.isMuted ? "Muted" : "\(Int((store.settings.volume * 100).rounded())) %",
                           tone: store.settings.isMuted ? .warning : .neutral)
            case .pane(.appearance):
                ValuePlate("\(Int(store.settings.wheelSize)) pt")
                ValuePlate("\(Int(store.settings.pingSize)) pt")
            case .pane(.permissions):
                ValuePlate(permissions.isGranted ? "Granted" : "Not granted",
                           tone: permissions.isGranted ? .success : .danger)
            case .pane(.about):
                ValuePlate("\(PingDefinition.all.count) pings")
                ValuePlate("\(EmoteDefinition.all.count) emotes")
            case .ping(let id):
                let definition = PingDefinition.definition(for: id)
                ValuePlate(definition.category.displayName)
                ValuePlate(sliceLabel(id))
            }
        }
    }

    /// The one fact a ping page is always about: whether that ping is reachable from the wheel.
    private func sliceLabel(_ ping: PingDefinition.ID) -> String {
        guard let slice = store.settings.wheelSlots.firstIndex(of: ping) else { return "not on wheel" }
        return "slice \(slice + 1)"
    }

    private var isLeagueWheel: Bool { store.settings.wheelSlots == PingDefinition.defaultWheel }

    private var stateWord: String {
        if !store.settings.isEnabled { return "Paused" }
        if !permissions.isGranted { return "Blocked" }
        return engine.tapStatus == .running ? "Running" : "Idle"
    }

    private var stateTone: ValuePlate.Tone {
        if !store.settings.isEnabled { return .warning }
        if !permissions.isGranted { return .danger }
        return engine.tapStatus == .running ? .success : .neutral
    }
}

// MARK: - Search results

/// What the search field leaves: a flat list of everything the window can open.
private struct SearchResults: View {
    @EnvironmentObject private var router: SettingsRouter

    var body: some View {
        let found = SettingsCatalog.results(query: router.query, scope: .all)
        VStack(alignment: .leading, spacing: Metrics.groupGap) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(found.count) result\(found.count == 1 ? "" : "s")")
                    .font(Metrics.eyebrow)
                    .tracking(1.1)
                    .foregroundStyle(Palette.tertiaryText)
                Spacer(minLength: 12)
                Text("“\(router.query)”")
                    .font(Metrics.caption)
                    .foregroundStyle(Palette.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 2)

            if found.isEmpty {
                InlineNote(text: "Nothing matches that. Try a ping name, a key, or what the setting does.")
                    .staggered(0)
            } else {
                SectionCard {
                    ForEach(Array(found.enumerated()), id: \.element.id) { offset, hit in
                        LineRow(hit.title, subtitle: hit.subtitle,
                                icon: AnyView(chip(for: hit)),
                                divider: offset > 0,
                                highlightID: hit.id,
                                action: {
                                    router.query = ""
                                    router.go(hit.destination)
                                    router.highlight = hit.id
                                }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.tertiaryText)
                        }
                    }
                }
                .staggered(1)
            }
        }
    }

    @ViewBuilder private func chip(for hit: SettingsCatalog.Hit) -> some View {
        if let id = hit.ping {
            PingChip(ping: PingDefinition.definition(for: id))
        } else if case .pane(let pane) = hit.destination {
            IconChip(symbol: pane.symbol)
        } else {
            IconChip(symbol: "gearshape")
        }
    }
}

extension SettingsRootView {
    /// Read once at startup; Reduce Motion should not make the interface jitter when the setting
    /// flips. The render harness asks for the settled state so a photograph is not half-drawn.
    static var isReduceMotion: Bool {
        if ProcessInfo.processInfo.environment["PINGFLOW_RENDER"] != nil { return true }
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// A texture re-stamped to the size it will be drawn, so a `.resizable()` image cannot report
    /// its 256 pt ideal size to a parent that measures with no proposal.
    static func sized(_ image: NSImage, to side: CGFloat) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: side, height: side)
        return copy
    }
}
