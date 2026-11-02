import AppKit
import SwiftUI

/// The keycap recorder from the Interaction page. It records through a local event monitor, which
/// is the right tool here: the settings window is key, the app is active, and nothing global is
/// touched. The global tap stands down only while this is recording, so the wheel still works with
/// the settings window open.
///
/// Three rules the page depends on:
/// * Escape while recording cancels and restores the old combination; it is never recorded.
/// * An unusable combination is refused with a sentence, not silently dropped.
/// * A combination something else already owns is refused until the user says otherwise.
struct ShortcutRecorderView: View {
    @EnvironmentObject private var engine: PingFlowEngine

    /// What is recorded now, or nil when unset.
    @Binding var combo: KeyCombo?
    /// Refused combinations: returns a person-shaped reason, e.g. "already used by Toggle wheel".
    var conflictFinder: (KeyCombo) -> String? = { _ in nil }
    /// A modifier-only combination is meaningless globally, so the recorder insists on a key.
    var requiresModifier = true
    var placeholder = "Click, then press a key"
    var width: CGFloat = 168

    @State private var recording = false
    @State private var message: String?
    @State private var rejected = false
    @State private var monitor: Any?
    @State private var hovered = false
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            keycaps
                .frame(width: width, alignment: .center)
                .frame(height: 30)
                .background(Palette.controlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: recording ? 1.5 : 1)
                )
                .overlay(alignment: .trailing) { clearButton }
                .contentShape(Rectangle())
                .onTapGesture { toggle() }
                .onHover { hovered = $0 }
                .scaleEffect(recording && pulse ? 1.015 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                .help(recording ? "Press a key · Escape cancels" : "Record a shortcut")

            if let message {
                Text(message)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(rejected ? Palette.danger : Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: width, alignment: .trailing)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: message)
        .animation(.spring(response: 0.26, dampingFraction: 0.8), value: recording)
        .onDisappear { stop() }
    }

    // MARK: - The keycap row

    @ViewBuilder private var keycaps: some View {
        HStack(spacing: 4) {
            if recording {
                Text("Press a key…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.accent)
            } else if let combo {
                ForEach(Array(combo.keycaps.enumerated()), id: \.offset) { _, cap in
                    Keycap(text: cap, accent: cap.count == 1 && isGlyph(cap))
                }
            } else {
                Text(placeholder)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 8)
    }

    private func isGlyph(_ text: String) -> Bool { "⌃⌥⇧⌘".contains(text) }

    private var borderColor: Color {
        if rejected { return Palette.danger }
        if recording { return Palette.accent }
        return hovered ? Palette.controlBorder : Palette.hairline
    }

    @ViewBuilder private var clearButton: some View {
        if !recording, combo != nil {
            Button {
                combo = nil
                say("Cleared. Nothing is bound to this.", bad: false)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.tertiaryText)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 7)
            .transition(.opacity)
        }
    }

    // MARK: - Recording

    private func toggle() {
        if recording {
            stop()
            say("Recording stopped.", bad: false)
        } else {
            start()
        }
    }

    private func start() {
        guard monitor == nil else { return }
        recording = true
        rejected = false
        message = "Press a key with at least one modifier."
        pulse = true
        engine.coordinator.recorderBegan()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
        }
    }

    private func stop() {
        // Only a live monitor owns a seat in the coordinator's count, so a stop that arrives twice
        // — Escape, then the view disappearing — cannot take the tap down with it.
        guard monitor != nil else {
            recording = false
            pulse = false
            return
        }
        NSEvent.removeMonitor(monitor!)
        monitor = nil
        engine.coordinator.recorderEnded()
        recording = false
        pulse = false
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        // Escape is the recorder's own cancel key; it never reaches the combo.
        if event.type == .keyDown, event.keyCode == KeyboardKey.escape {
            stop()
            rejected = false
            message = nil
            return nil
        }
        if event.type == .flagsChanged {
            // Live feedback while the modifiers go down, before the key is chosen.
            let modifiers = ModifierSet(event.modifierFlags)
            if !modifiers.isEmpty, combo == nil || event.modifierFlags.intersection([.command, .option, .control, .shift]) != [] {
                message = "\(modifiers.glyphs) …"
                rejected = false
            }
            return nil
        }
        guard event.type == .keyDown else { return event }
        let candidate = KeyCombo(keyCode: event.keyCode, modifiers: ModifierSet(event.modifierFlags))
        guard commit(candidate) else { return nil }
        stop()
        return nil
    }

    /// Validates, then writes. False means the recorder stays open so the user can try again.
    private func commit(_ candidate: KeyCombo) -> Bool {
        if KeyboardKey.isModifierKey(Int(candidate.keyCode)) {
            say("That is a modifier on its own. Add a letter, number or function key.", bad: true)
            return false
        }
        if KeyboardKey.isBlockedShortcutKey(Int(candidate.keyCode)) {
            let name = KeyboardKey.name(for: Int(candidate.keyCode))
            say("\(name.isEmpty ? "That key" : name) is reserved by the system and cannot be a shortcut.", bad: true)
            return false
        }
        if requiresModifier, candidate.modifiers.isEmpty {
            say("A global shortcut needs at least one modifier — \(candidate.keyName) alone would swallow every keystroke.", bad: true)
            return false
        }
        if !candidate.isValidGlobalShortcut {
            say("macOS will not accept that combination.", bad: true)
            return false
        }
        if let reason = conflictFinder(candidate) {
            say("\(candidate.displayString) is already \(reason). Pick another, or change the other one first.", bad: true)
            return false
        }
        combo = candidate
        rejected = false
        say("Bound to \(candidate.displayString).", bad: false)
        return true
    }

    private func say(_ text: String, bad: Bool) {
        message = text
        rejected = bad
        if !bad {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if message == text { message = nil }
            }
        }
    }
}

/// One physical key drawn as a keycap: the modifier glyphs and the chosen key, the way macOS
/// writes a shortcut, but as separate chips instead of one run-on string.
struct Keycap: View {
    let text: String
    var accent = false
    var side: CGFloat? = nil

    @State private var hovered = false

    var body: some View {
        Text(text)
            .font(.system(size: accent ? 13 : 11.5, weight: .semibold, design: .default))
            .foregroundStyle(accent ? Palette.accent : Palette.primaryText)
            .frame(minWidth: side ?? (accent ? 24 : 22), minHeight: 22, maxHeight: 22)
            .padding(.horizontal, side == nil ? 4 : 0)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hovered ? Palette.controlHover : Palette.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(accent ? Palette.accent.opacity(0.5) : Palette.controlBorder, lineWidth: 1)
            )
            .shadow(color: Palette.cardShadow, radius: 0.5, y: 0.5)
            .animation(.easeOut(duration: 0.12), value: hovered)
            .onHover { hovered = $0 }
    }
}

/// The activation key, chosen as keycaps rather than a menu: one tap and the modifier is set.
struct ModifierKeyPicker: View {
    @Binding var selection: ActivationModifier
    var exclude: ActivationModifier? = nil
    var onPick: ((ActivationModifier) -> Void)? = nil

    @State private var hovered: ActivationModifier?

    var body: some View {
        HStack(spacing: 5) {
            ForEach(ActivationModifier.allCases) { modifier in
                Button {
                    guard modifier != exclude else { return }
                    selection = modifier
                    onPick?(modifier)
                } label: {
                    VStack(spacing: 2) {
                        Text(modifier.glyph)
                            .font(.system(size: 15, weight: .medium))
                        Text(modifier.displayName.prefix(1))
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(style(for: modifier).0)
                    .frame(width: 34, height: 32)
                    .background(style(for: modifier).1, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(selection == modifier ? Palette.accent
                                            : hovered == modifier ? Palette.controlBorder : Palette.hairline,
                                          lineWidth: selection == modifier ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(modifier == exclude)
                .onHover { hovered = $0 ? modifier : (hovered == modifier ? nil : hovered) }
                .accessibilityLabel(modifier.displayName)
                .accessibilityAddTraits(selection == modifier ? .isSelected : [])
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.8), value: selection)
    }

    private func style(for modifier: ActivationModifier) -> (Color, Color) {
        if selection == modifier { return (Palette.accent, Palette.selection) }
        if modifier == exclude { return (Palette.tertiaryText, .clear) }
        return (Palette.secondaryText, Palette.controlBackground)
    }
}
