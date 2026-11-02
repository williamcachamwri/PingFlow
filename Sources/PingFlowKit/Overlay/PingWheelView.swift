import AppKit
import CoreImage
import SwiftUI

/// Bakes the wheel's idle icon look — the reference's CSS chain `grayscale(1) sepia(.75)
/// saturate(1.3) brightness(1.15)`, as closely as Core Image allows — into a cached image.
/// Doing it once per icon keeps hover on the GPU instead of a filter applied every frame.
enum TintedIconCache {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])
    private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()

    static func tinted(_ image: NSImage, key: String) -> NSImage {
        lock.lock()
        if let cached = cache[key] { lock.unlock(); return cached }
        lock.unlock()

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        var ci = CIImage(cgImage: cgImage)
        let chain: [(String, [String: Any])] = [
            ("CIGrayscale", ["inputIntensity": 1.0]),
            ("CISepiaTone", ["inputIntensity": 0.75]),
            ("CIColorControls", ["inputSaturation": 1.3, "inputBrightness": 0.08]),
        ]
        for (name, parameters) in chain {
            guard let filter = CIFilter(name: name) else { continue }
            filter.setValue(ci, forKey: kCIInputImageKey)
            for (parameter, value) in parameters { filter.setValue(value, forKey: parameter) }
            guard let output = filter.outputImage?.cropped(to: ci.extent) else { continue }
            ci = output
        }
        guard let output = context.createCGImage(ci, from: ci.extent) else { return image }
        let tinted = NSImage(cgImage: output, size: image.size)
        lock.lock()
        cache[key] = tinted
        lock.unlock()
        return tinted
    }
}

/// One annulus sector: the shape League's wheel slices are cut from.
struct SectorShape: Shape {
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var startAngle: Double
    var endAngle: Double

    /// Compass-screen degrees: 0 east, 90 south — the same sense as `atan2` with y pointing down,
    /// which is how the reference's SVG and `pickSlice` both measure angles.
    private func offset(radius: CGFloat, degrees: Double) -> CGPoint {
        let radians = CGFloat(degrees) * .pi / 180
        return CGPoint(x: radius * cos(radians), y: radius * sin(radians))
    }

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        func at(_ radius: CGFloat, _ degrees: Double) -> CGPoint {
            let offset = self.offset(radius: radius, degrees: degrees)
            return CGPoint(x: centre.x + offset.x, y: centre.y + offset.y)
        }
        var path = Path()
        path.move(to: at(innerRadius, startAngle))
        path.addLine(to: at(outerRadius, startAngle))
        path.addArc(center: centre, radius: outerRadius,
                    startAngle: .degrees(startAngle), endAngle: .degrees(endAngle), clockwise: false)
        path.addLine(to: at(innerRadius, endAngle))
        path.addArc(center: centre, radius: innerRadius,
                    startAngle: .degrees(endAngle), endAngle: .degrees(startAngle), clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// The wheel itself, as one real component: the overlay and the settings editor draw the same
/// view, so what you arrange is literally what you get.
struct PingWheelView: View {
    let slots: [PingDefinition.ID]
    var hoveredSlice: Int?
    var confirmedSlice: Int?
    var size: CGFloat
    var dimUnhoveredIcons = true
    var showCentreLabel = true
    var centreText: String = "PING"
    var hubImageName: String = PingDefinition.logoTexture
    /// The editor draws a smaller wheel; the overlay keeps the reference's proportions.
    var geometry: WheelGeometry = .reference
    /// Hover and tap are only live in the editor. The overlay's panel ignores the mouse.
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
        .animation(.easeOut(duration: 0.10), value: dimUnhoveredIcons)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ping wheel")
    }

    // MARK: - Layers, in the order the reference draws them

    /// The 86→188 ring, painted as a stroked circle so its gradient runs true with the radius.
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

    /// N, E, S and W reach out to 288 with a fade, the way League's wheel points the cardinal ways.
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

    /// The hover wash: the gradient the reference fills a hot wedge with, at 0.55 opacity.
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

    /// Thin gold-tinted lines between slices: the wheel's only ornament.
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

    /// Icons sit at radius 137. Idle ones wear the gold tint; the hovered one shows its real
    /// colours at 1.18× — the whole selection language of the wheel.
    private func sliceIcons(layout: WheelLayout) -> some View {
        ZStack {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, pingID in
                let definition = PingDefinition.definition(for: pingID)
                let isHot = hoveredSlice == index
                let offset = layout.iconCentre(forSlice: index)
                let centre = CGPoint(x: size / 2 + offset.x, y: size / 2 + offset.y)
                ZStack {
                    if dimUnhoveredIcons {
                        iconLayer(definition: definition, tinted: true)
                    }
                    iconLayer(definition: definition, tinted: false)
                        .opacity(dimUnhoveredIcons ? (isHot ? 1 : 0) : 1)
                }
                .frame(width: layout.iconSize, height: layout.iconSize)
                .scaleEffect(isHot ? 1.18 : 1)
                .position(centre)
                .animation(.easeOut(duration: 0.10), value: isHot)
                .animation(.spring(response: 0.22, dampingFraction: 0.62), value: isHot)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func iconLayer(definition: PingDefinition, tinted: Bool) -> some View {
        if let image = AssetCatalog.shared.image(named: definition.iconTexture) {
            Image(nsImage: tinted ? TintedIconCache.tinted(image, key: definition.iconTexture) : image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            // No asset, no blank slice: a drawn disc in the ping's own colour.
            Circle()
                .fill(Color(hex: definition.colorHex))
                .opacity(tinted ? 0.45 : 0.9)
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
        }
    }

    /// The teal core with its gold ring, the hub icon, the label and the BACK hint — placed at
    /// the same offsets the reference's SVG uses (hub at -38, text at +6, hint at +50).
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

            if let hub = AssetCatalog.shared.image(named: hubImageName) {
                Image(nsImage: hub)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40 * scale, height: 40 * scale)
                    .position(x: size / 2, y: size / 2 - 38 * scale)
            }

            if showCentreLabel {
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
            }

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

    // MARK: - Pointer tracking, live only in the editor

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

/// The right-click mouse drawn next to BACK: an outline with the left button filled.
struct RightClickMouseGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: width / 2, style: .continuous)
                    .strokeBorder(lineWidth: 1.3)
                Path { path in
                    path.move(to: CGPoint(x: width / 2, y: 0))
                    path.addLine(to: CGPoint(x: width, y: 0))
                    path.addLine(to: CGPoint(x: width, y: height * 0.44))
                    path.addArc(center: CGPoint(x: width / 2, y: height * 0.44), radius: width / 2,
                                startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
                    path.closeSubpath()
                }
                .fill(.primary)
            }
        }
    }
}

extension Color {
    /// "#rrggbb", the format the ping table and the accent swatches store.
    init(hex: String) {
        var string = hex
        if string.hasPrefix("#") { string.removeFirst() }
        if string.count == 3 { string = string.map { "\($0)\($0)" }.joined() }
        let value = UInt64(string, radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
