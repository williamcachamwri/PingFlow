import AppKit
import SwiftUI

/// Volume, mute and the wheel's tick. Every preview goes through the same engine the wheel uses, so
/// what you hear here is what a ping sounds like in a game.
struct SoundsPane: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var audio: AudioEngine

    @State private var reduceMotion = SettingsRootView.isReduceMotion

    private var settings: AppSettings { store.settings }

    var body: some View {
        SettingsPage {
            SectionCard("Output", highlightID: "volume") {
                LineRow("Master volume", highlightID: "volume") {
                    MeasuredSlider(value: volumeBinding, range: 0...1,
                                   label: "Master volume") { value in
                        "\(Int((value * 100).rounded())) %"
                    }
                }
                LineRow("Mute everything", divider: true, highlightID: "isMuted") {
                    PingSwitch(isOn: store.binding(\.isMuted))
                }
                LineRow("Ping sounds", divider: true, highlightID: "pingSoundsEnabled") {
                    PingSwitch(isOn: store.binding(\.pingSoundsEnabled))
                }
            }
            .staggered(0, enabled: !reduceMotion)

            SectionCard("The wheel's tick", highlightID: "tickSoundEnabled") {
                LineRow("Selection sound", highlightID: "tickSoundEnabled") {
                    PingSwitch(isOn: store.binding(\.tickSoundEnabled))
                }
                LineRow("Level", divider: true, highlightID: "tickVolume") {
                    HStack(spacing: 10) {
                        MeasuredSlider(value: store.binding(\.tickVolume), range: 0...1,
                                       plateWidth: 48, label: "Tick level") { value in
                            "\(Int((value * 100).rounded())) %"
                        }
                        Button("Play") {
                            audio.play(soundName: PingDefinition.tickSound,
                                       level: max(0.35, settings.tickVolume))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                if !audio.canPlay(PingDefinition.tickSound) {
                    Hairline(inset: Metrics.rowPadding)
                    LineRow("button.wav is missing",
                            subtitle: "The tick is League's own file; Assets/sounds does not have it.",
                            icon: AnyView(IconChip(symbol: "speaker.slash", tint: Palette.warning))) {
                        EmptyView()
                    }
                }
            }
            .staggered(1, enabled: !reduceMotion)
        }
        .onAppear { audio.startIfNeeded() }
    }

    /// Writing 0 through the binding would fight `normalized()`'s clamping; the volume is honest.
    private var volumeBinding: Binding<Double> {
        Binding(get: { settings.isMuted ? 0 : settings.volume },
                set: { newValue in store.update { $0.volume = newValue; if newValue > 0 { $0.isMuted = false } } })
    }
}
