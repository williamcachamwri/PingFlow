import AppKit
import SwiftUI

struct InteractionPane: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var permissions: PermissionManager

    @State private var reduceMotion = SettingsRootView.isReduceMotion

    private var settings: AppSettings { store.settings }

    var body: some View {
        SettingsPage {
            SectionCard("Keys", highlightID: "activationKey") {
                LineRow("Wheel key", highlightID: "activationKey") {
                    ModifierKeyPicker(selection: store.binding(\.activationKey),
                                      exclude: settings.secondaryActivationKey)
                }
                LineRow("Also accept", divider: true, highlightID: "secondaryActivationKey") {
                    Segmented(alternativeOptions, selection: alternativeBinding) { option in
                        Text(option.glyph)
                            .frame(minWidth: 22)
                    }
                }
                LineRow("Toggle shortcut", divider: true, highlightID: "toggleShortcut") {
                    ShortcutRecorderView(combo: store.binding(\.toggleShortcut),
                                         conflictFinder: systemConflict,
                                         placeholder: "None — click to set",
                                         width: 176)
                }
            }
            .staggered(0, enabled: !reduceMotion)

            SectionCard("Pointer", highlightID: "dragThreshold") {
                LineRow("Drag threshold", highlightID: "dragThreshold") {
                    MeasuredSlider(value: store.binding(\.dragThreshold), range: 2...40, step: 1,
                                   label: "Drag threshold") { value in "\(Int(value)) pt" }
                }
                LineRow("Left click", divider: true, highlightID: "clickBehaviour") {
                    Segmented(ClickBehaviour.allCases, selection: store.binding(\.clickBehaviour)) { behaviour in
                        Text(behaviour.displayName)
                            .frame(minWidth: 40)
                    }
                }
            }
            .staggered(1, enabled: !reduceMotion)

            SectionCard("Escape hatches") {
                LineRow("Right click cancels", highlightID: "cancelOnRightClick") {
                    PingSwitch(isOn: store.binding(\.cancelOnRightClick))
                }
                LineRow("Other keys cancel", divider: true, highlightID: "cancelOnOtherKeyPress") {
                    PingSwitch(isOn: store.binding(\.cancelOnOtherKeyPress))
                }
            }
            .staggered(2, enabled: !reduceMotion)
        }
    }

    private enum Alternative: String, CaseIterable, Identifiable, Hashable {
        case none, option, control, shift, command
        var id: String { rawValue }
        var glyph: String {
            switch self {
            case .none: return "—"
            case .option: return "⌥"
            case .control: return "⌃"
            case .shift: return "⇧"
            case .command: return "⌘"
            }
        }
    }

    private var alternativeOptions: [Alternative] { Alternative.allCases }

    private var alternativeBinding: Binding<Alternative> {
        Binding(
            get: {
                guard let secondary = settings.secondaryActivationKey else { return .none }
                switch secondary {
                case .option: return .option
                case .control: return .control
                case .shift: return .shift
                case .command: return .command
                }
            },
            set: { newValue in
                store.update {
                    switch newValue {
                    case .none: $0.secondaryActivationKey = nil
                    case .option: $0.secondaryActivationKey = .option
                    case .control: $0.secondaryActivationKey = .control
                    case .shift: $0.secondaryActivationKey = .shift
                    case .command: $0.secondaryActivationKey = .command
                    }
                }
            }
        )
    }

    private func systemConflict(_ combo: KeyCombo) -> String? {
        let control = combo.modifiers.containsControl
        let option = combo.modifiers.containsOption
        let shift = combo.modifiers.containsShift
        let command = combo.modifiers.containsCommand
        let onlyControl = control && !option && !shift && !command
        let onlyCommand = command && !control && !option && !shift
        let keyCode = Int(combo.keyCode)
        if keyCode == KeyboardKey.space, onlyCommand { return "Spotlight" }
        if keyCode == KeyboardKey.space, control && command { return "Character viewer" }
        if onlyControl, keyCode == 123 || keyCode == 124 || keyCode == 126 { return "Mission Control" }
        if keyCode == 96, control && command { return "Input source switch" }
        return nil
    }
}
