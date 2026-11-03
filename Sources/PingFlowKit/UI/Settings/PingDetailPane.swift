import AppKit
import SwiftUI

/// One ping's own page — what a search hit opens onto. It is not a summary: the slice, the centre
/// and the sound are written through the same store the gesture reads, so changing them here
/// changes the next key press.
struct PingDetailPane: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var engine: PingFlowEngine
    @EnvironmentObject private var audio: AudioEngine
    @EnvironmentObject private var router: SettingsRouter

    let pingID: PingDefinition.ID

    @StateObject private var stage = PingStage()
    @State private var reduceMotion = SettingsRootView.isReduceMotion

    private var definition: PingDefinition { PingDefinition.definition(for: pingID) }
    private var slots: [PingDefinition.ID] { store.settings.wheelSlots }
    private var slice: Int? { slots.firstIndex(of: pingID) }
    private var isCentre: Bool { store.settings.clickPing == pingID }

    var body: some View {
        SettingsPage {
            SectionCard("On the wheel", highlightID: "ping-\(pingID.rawValue)") {
                LineRow("Slice", icon: AnyView(PingChip(ping: definition))) {
                    PillMenu(sliceOptions, selection: sliceBinding) { option in
                        Text(option.label)
                    }
                }
                LineRow("Centre", divider: true, highlightID: "clickPing", action: { setCentre() }) {
                    if isCentre {
                        ValuePlate("In the centre", tone: .accent)
                    } else {
                        GoMark()
                    }
                }
            }
            .staggered(0, enabled: !reduceMotion)

            SectionCard("Sound") {
                LineRow("Callout", icon: AnyView(IconChip(symbol: "speaker.wave.2"))) {
                    HStack(spacing: 10) {
                        Button {
                            audio.play(definition)
                        } label: {
                            Image(systemName: "play.circle")
                                .font(.system(size: 15))
                                .foregroundStyle(Palette.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .help("Play \(definition.name)")
                        RayCheck(state: soundState, onChange: { setSound($0) })
                    }
                }
                LineRow("Ping sounds", divider: true, highlightID: "pingSoundsEnabled") {
                    PingSwitch(isOn: store.binding(\.pingSoundsEnabled))
                }
                if !audio.canPlay(definition.sound) {
                    Hairline(inset: Metrics.rowPadding)
                    LineRow("\(definition.sound).wav is missing",
                            icon: AnyView(IconChip(symbol: "exclamationmark.triangle", tint: Palette.warning))) {
                        EmptyView()
                    }
                }
            }
            .staggered(1, enabled: !reduceMotion)

            SectionCard("How it lands",
                        trailing: AnyView(
                            HStack(spacing: 6) {
                                ValuePlate("\(Int(store.settings.pingSize)) pt")
                                ValuePlate(String(format: "%.1f s", store.settings.pingDuration))
                            }
                        )) {
                AnimationPreviewBox(stage: stage,
                                    height: 120,
                                    definition: definition,
                                    settings: store.settings,
                                    playToken: 0,
                                    onPlay: { audio.play(definition) })
                    .padding(.horizontal, Metrics.rowPadding)
                    .padding(.vertical, 14)
                Hairline()
                LineRow("Send it at my pointer", action: { engine.coordinator.preview(definition: definition) }) {
                    GoMark()
                }
            }
            .staggered(2, enabled: !reduceMotion)

            SectionCard("Jump to") {
                LineRow("Ping Wheel", icon: AnyView(IconChip(symbol: "circle.hexagongrid")),
                        action: { router.go(.pane(.pingWheel)) }) { GoMark() }
                LineRow("Sounds", icon: AnyView(IconChip(symbol: "speaker.wave.2")), divider: true,
                        action: { router.go(.pane(.sounds)) }) { GoMark() }
            }
            .staggered(3, enabled: !reduceMotion)
        }
    }

    // MARK: - Slice

    private enum SliceOption: Hashable, Identifiable {
        case slice(Int)
        var id: Int { switch self { case .slice(let index): return index } }
        var label: String {
            switch self {
            case .slice(let index): return "\(index + 1) · \(Self.compass(index))"
            }
        }
        static func compass(_ index: Int) -> String {
            ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][index % 8]
        }
    }

    private var sliceOptions: [SliceOption] { (0..<PingDefinition.wheelSlotCount).map { .slice($0) } }

    /// Choosing the slice this ping already holds is the no-op case, so the menu has a value even
    /// when the ping sits off the wheel.
    private var sliceBinding: Binding<SliceOption> {
        Binding(get: { .slice(slice ?? 0) },
                set: { option in
                    guard case .slice(let index) = option else { return }
                    applyPlacement(index)
                })
    }

    private func applyPlacement(_ index: Int) {
        guard let next = WheelEditor.place(slots, ping: pingID, at: index) else { return }
        store.update { $0.wheelSlots = next }
        tick()
    }

    private func setCentre() {
        store.update { $0.clickPing = pingID }
        tick()
    }

    // MARK: - Sound

    private var soundState: RayCheck.CheckState {
        if !store.settings.pingSoundsEnabled { return store.settings.disabledPingSounds.contains(pingID) ? .off : .indeterminate }
        return store.settings.isPingSoundEnabled(pingID) ? .on : .off
    }

    private func setSound(_ on: Bool) {
        store.update {
            $0.pingSoundsEnabled = true
            if on {
                $0.disabledPingSounds.removeAll { $0 == pingID }
            } else if !$0.disabledPingSounds.contains(pingID) {
                $0.disabledPingSounds.append(pingID)
            }
        }
        tick()
    }

    // MARK: - Small helpers

    private func tick() {
        guard store.settings.tickSoundEnabled else { return }
        audio.play(soundName: PingDefinition.tickSound, level: store.settings.tickVolume)
    }
}
