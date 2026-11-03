import AppKit
import SwiftUI

/// The emote wheel: same ring geometry as the ping wheel, but icons keep their original colours
/// and are clipped to circles instead of wearing the gold tint.
struct EmoteWheelView: View {
    let slots: [EmoteKey]
    var hoveredSlice: Int?
    var confirmedSlice: Int?
    var size: CGFloat
    var centreText: String = "EMOTE"
    var geometry: WheelGeometry = .reference
    var interactive = false
    var onHover: ((Int?) -> Void)? = nil
    var onPick: ((Int) -> Void)? = nil

    private var layout: WheelLayout { WheelLayout(size: size, geometry: geometry) }

    var body: some View {
        let layout = self.layout
        ZStack {
            baseRing(layout: layout)
            cardinalExtensions(layout: layout)
            sliceHighlights(layout: layout)
            sliceDividers(layout: layout)
            sliceIcons(layout: layout)
            centreDisc(layout: layout)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .overlay(alignment: .topLeading) { hoverCatcher(layout: layout) }
        .animation(.easeOut(duration: 0.08), value: hoveredSlice)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Emote wheel")
    }

    // MARK: - Layers

    private func baseRing(layout: WheelLayout) -> some View {
        let radius = (layout.innerRadius + layout.outerRadius) / 2
        let width = layout.outerRadius - layout.innerRadius
        return Circle()
            .stroke(
                RadialGradient(
                    stops: [
                        .init(color: Color(hex: "#2a2d31"), location: 0),
                        .init(color: Color(hex: "#2a2d31"), location: layout.innerRadius / layout.outerRadius),
                        .init(color: Color(hex: "#4a4e54"), location: 1),
                    ],
                    center: .center, startRadius: 0, endRadius: layout.outerRadius
                ),
                lineWidth: width
            )
            .frame(width: radius * 2, height: radius * 2)
            .opacity(0.92)
    }

    private func cardinalExtensions(layout: WheelLayout) -> some View {
        ZStack {
            ForEach([0, 2, 4, 6], id: \.self) { index in
                let mid = Double(WheelGeometry.centreAngle(of: index))
                SectorShape(innerRadius: layout.outerRadius, outerRadius: layout.extensionRadius,
                            startAngle: mid - 22.5, endAngle: mid + 22.5)
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: Color(hex: "#5c6066").opacity(0.55), location: 0),
                                .init(color: Color(hex: "#5c6066").opacity(0.55),
                                      location: layout.outerRadius / layout.extensionRadius),
                                .init(color: Color(hex: "#5c6066").opacity(0), location: 1),
                            ],
                            center: .center, startRadius: 0, endRadius: layout.extensionRadius
                        )
                    )
            }
        }
        .frame(width: size, height: size)
    }

    private func sliceHighlights(layout: WheelLayout) -> some View {
        ZStack {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, _ in
                let mid = Double(WheelGeometry.centreAngle(of: index))
                let isHot = hoveredSlice == index
                let isConfirmed = confirmedSlice == index
                SectorShape(innerRadius: layout.innerRadius,
                            outerRadius: layout.outerRadius(forSlice: index),
                            startAngle: mid - 22.5, endAngle: mid + 22.5)
                    .fill(hotGradient(layout: layout))
                    .opacity(isHot ? 0.55 : (isConfirmed ? 0.7 : 0))
            }
        }
        .frame(width: size, height: size)
    }

    private func hotGradient(layout: WheelLayout) -> RadialGradient {
        RadialGradient(
            stops: [
                .init(color: Color(hex: "#8a8f96"), location: 0),
                .init(color: Color(hex: "#8a8f96"), location: layout.innerRadius / layout.extensionRadius),
                .init(color: Color(hex: "#9aa0a8"), location: layout.outerRadius / layout.extensionRadius),
                .init(color: Color(hex: "#9aa0a8").opacity(0), location: 1),
            ],
            center: .center, startRadius: 0, endRadius: layout.extensionRadius
        )
    }

    private func sliceDividers(layout: WheelLayout) -> some View {
        Canvas { context, _ in
            let centre = CGPoint(x: size / 2, y: size / 2)
            for index in 0..<WheelGeometry.sliceCount {
                let edge = Double(WheelGeometry.centreAngle(of: index)) - 22.5
                let inner = WheelGeometry.point(radius: layout.innerRadius, degrees: CGFloat(edge))
                let outer = WheelGeometry.point(radius: layout.outerRadius, degrees: CGFloat(edge))
                var path = Path()
                path.move(to: CGPoint(x: centre.x + inner.x, y: centre.y + inner.y))
                path.addLine(to: CGPoint(x: centre.x + outer.x, y: centre.y + outer.y))
                context.stroke(path, with: .color(Color(hex: "#a08a5c").opacity(0.45)), lineWidth: 1.2)
            }
        }
        .frame(width: size, height: size)
    }

    /// Emote icons: circular-clipped, full colour, no tint. The key visual difference from the
    /// ping wheel. Imported art animates only on the slice you are aiming at.
    private func sliceIcons(layout: WheelLayout) -> some View {
        ZStack {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, emoteKey in
                let isHot = hoveredSlice == index
                let offset = layout.iconCentre(forSlice: index)
                let centre = CGPoint(x: size / 2 + offset.x, y: size / 2 + offset.y)
                emoteIcon(key: emoteKey, animates: isHot)
                    .frame(width: layout.iconSize, height: layout.iconSize)
                    .clipShape(Circle())
                    .scaleEffect(isHot ? 1.18 : 1)
                    .position(centre)
                    .animation(.easeOut(duration: 0.10), value: isHot)
                    .animation(.spring(response: 0.22, dampingFraction: 0.62), value: isHot)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func emoteIcon(key: EmoteKey, animates: Bool) -> some View {
        if let asset = EmoteLibrary.shared.asset(for: key) {
            EmoteArtView(asset: asset, animates: animates, corner: 0)
                .accessibilityHidden(true)
        } else {
            Circle()
                .fill(Color(hex: "#4a4e54"))
                .overlay(
                    Text(String(EmoteLibrary.shared.name(for: key).prefix(2)).uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
    }

    private func centreDisc(layout: WheelLayout) -> some View {
        let scale = layout.scale
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(stops: [
                        .init(color: Color(hex: "#2c5d60"), location: 0),
                        .init(color: Color(hex: "#11292c"), location: 1),
                    ], center: UnitPoint(x: 0.5, y: 0.5 - 10 / layout.innerRadius * 0.5),
                       startRadius: 0, endRadius: layout.innerRadius)
                )
                .frame(width: layout.innerRadius * 2, height: layout.innerRadius * 2)
                .overlay(Circle().stroke(Color(hex: "#c8aa6e"), lineWidth: 3))

            Circle()
                .stroke(Color(hex: "#8a7448").opacity(0.6), lineWidth: 1)
                .frame(width: (layout.innerRadius - 7) * 2, height: (layout.innerRadius - 7) * 2)

            Circle()
                .stroke(Color(hex: "#1a1a1a").opacity(0.6), lineWidth: 6)
                .frame(width: (layout.innerRadius + 4) * 2, height: (layout.innerRadius + 4) * 2)

            Text(centreText)
                .font(.system(size: 15 * scale, weight: .semibold))
                .tracking(1 * scale)
                .foregroundStyle(Color(hex: "#1fa9e0"))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .padding(.horizontal, 12 * scale)
                .frame(width: layout.innerRadius * 2, height: 22 * scale)
                .position(x: size / 2, y: size / 2 + 6 * scale)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.10), value: centreText)

            HStack(spacing: 3 * scale) {
                RightClickMouseGlyph()
                    .frame(width: 11 * scale, height: 16 * scale)
                    .foregroundStyle(Color(hex: "#6c7a7c"))
                Text("BACK")
                    .font(.system(size: 9 * scale, weight: .semibold))
                    .tracking(0.5 * scale)
                    .foregroundStyle(Color(hex: "#6c7a7c"))
            }
            .opacity(0.55)
            .position(x: size / 2 + 6 * scale, y: size / 2 + 50 * scale)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Pointer tracking

    @ViewBuilder
    private func hoverCatcher(layout: WheelLayout) -> some View {
        if interactive {
            Color.clear
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let index = WheelGeometry.sliceIndex(dx: location.x - size / 2,
                                                             dy: location.y - size / 2,
                                                             deadZone: layout.innerRadius)
                        onHover?(index >= 0 ? index : nil)
                    case .ended:
                        onHover?(nil)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onEnded { value in
                            let index = WheelGeometry.sliceIndex(dx: value.location.x - size / 2,
                                                                 dy: value.location.y - size / 2,
                                                                 deadZone: layout.innerRadius)
                            if index >= 0 { onPick?(index) }
                        }
                )
        }
    }
}
