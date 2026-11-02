import AppKit
import SwiftUI

struct AppearancePane: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var engine: PingFlowEngine
    @EnvironmentObject private var audio: AudioEngine

    @StateObject private var stage = PingStage()
    @State private var reduceMotion = SettingsRootView.isReduceMotion
    @State private var previewPing: PingDefinition.ID = .danger
    @State private var playToken = 0

    private let fxHeight: CGFloat = 140

    private var previewPingBinding: Binding<PingDefinition> {
        Binding(get: { PingDefinition.definition(for: previewPing) },
                set: { previewPing = $0.id })
    }

    var body: some View {
        SettingsPage {
            SectionCard("The wheel", highlightID: "wheelSize") {
                LineRow("Wheel size", highlightID: "wheelSize") {
                    MeasuredSlider(value: store.binding(\.wheelSize), range: 300...900, step: 10,
                                   label: "Wheel size") { value in "\(Int(value)) pt" }
                }
                LineRow("Opacity", divider: true, highlightID: "overlayOpacity") {
                    MeasuredSlider(value: store.binding(\.overlayOpacity), range: 0.35...1, step: 0.05,
                                   label: "Wheel opacity") { value in
                        "\(Int((value * 100).rounded())) %"
                    }
                }
                LineRow("Wheel colour", divider: true, highlightID: "accentColor") {
                    SwatchPicker(AccentColorChoice.allCases, selection: store.binding(\.accentColor),
                                 color: { Color(hex: $0.hex) }, name: { $0.displayName })
                }
            }
            .staggered(0, enabled: !reduceMotion)

            SectionCard("The mark") {
                LineRow("Ping size", highlightID: "pingSize") {
                    MeasuredSlider(value: store.binding(\.pingSize), range: 60...220, step: 5,
                                   label: "Ping size") { value in "\(Int(value)) pt" }
                }
                LineRow("Lifetime", divider: true, highlightID: "pingDuration") {
                    MeasuredSlider(value: store.binding(\.pingDuration), range: 1...8, step: 0.1,
                                   label: "Ping lifetime") { value in String(format: "%.1f s", value) }
                }
                LineRow("Intensity", divider: true, highlightID: "animationIntensity") {
                    MeasuredSlider(value: store.binding(\.animationIntensity), range: 0...1.5, step: 0.05,
                                   label: "Animation intensity") { value in
                        "\(Int((value * 100).rounded())) %"
                    }
                }
            }
            .staggered(1, enabled: !reduceMotion)

            SectionCard("Preview", highlightID: "preview") {
                LineRow("Ping", highlightID: "previewPing") {
                    PillMenu(PingDefinition.all, selection: previewPingBinding) { definition in
                        HStack(spacing: 6) {
                            PingIcon(ping: definition, side: 14)
                            Text(definition.name)
                        }
                    }
                }
                Hairline(inset: Metrics.rowPadding)
                AnimationPreviewBox(stage: stage,
                                    height: fxHeight,
                                    definition: PingDefinition.definition(for: previewPing),
                                    settings: store.settings,
                                    playToken: playToken,
                                    onPlay: { audio.play(PingDefinition.definition(for: previewPing)) })
                    .padding(.horizontal, Metrics.rowPadding)
                    .padding(.vertical, 14)
            }
            .staggered(2, enabled: !reduceMotion)
        }
    }
}

struct AnimationPreviewBox: View {
    @ObservedObject var stage: PingStage
    let height: CGFloat
    let definition: PingDefinition
    let settings: AppSettings
    let playToken: Int
    var onPlay: () -> Void = {}

    @State private var width: CGFloat = 260
    @State private var hovering = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.insetCorner, style: .continuous)
                    .fill(Palette.inset)
                PingFxHost(stage: stage, canvasHeight: height)
                    .allowsHitTesting(false)
                Image(systemName: "cursorarrow.click")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.tertiaryText.opacity(hovering ? 0 : 0.9))
                    .animation(.easeOut(duration: 0.2), value: hovering)
            }
            .onAppear { width = proxy.size.width }
            .onChange(of: proxy.size.width) { width = $0 }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.insetCorner, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { fire() }
        .onHover { hovering = $0 }
        .onChange(of: playToken) { _ in fire() }
        .help("Click to send it here")
    }

    private func fire() {
        stage.spawn(definition: definition,
                    at: CGPoint(x: max(60, width / 2), y: height / 2),
                    settings: settings)
        onPlay()
    }
}
