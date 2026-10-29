import CoreGraphics
import Foundation

/// LidKeeper's logo: a laptop with its lid ajar and the screen's light
/// spilling out toward the base.
///
/// It's drawn in code rather than shipped as a picture so the app icon and
/// the menu-bar glyph are one design, and both stay sharp at every size.
/// The shapes are traced from the original artwork, Design/logo-artwork.png
/// (1024 pixels wide), and kept in its coordinates with y pointing down;
/// each drawing function maps them into the rect it's given.
public enum Logo {

    // MARK: - App icon

    /// Draws the full-colour app icon on a `side`-pixel square canvas, laid
    /// out on the macOS icon grid: an 824/1024 tile with room for its shadow.
    ///
    /// Small sizes get the treatment Apple recommends: the laptop fills more
    /// of the tile, lines never go thinner than a pixel, and detail that
    /// would only turn to mush is left out.
    public static func drawAppIcon(in ctx: CGContext, side: CGFloat) {
        let unit = side / 1024
        let tile = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
        // The pressed-in outline, the ports and the grain only read from 256 px up.
        let detailed = side >= 256

        drawTile(in: ctx, rect: tile, unit: unit, detailed: detailed)

        // The laptop's share of the tile's width, and the thinnest line, in
        // pixels, that still reads at this size.
        let share: CGFloat = side >= 128 ? 0.74 : side >= 64 ? 0.80 : 0.86
        let thinnest: CGFloat = side >= 256 ? 1 : side >= 128 ? 1.4 : side >= 64 ? 1.25 : 1
        let width = tile.width * share
        let height = width * artBounds.height / artBounds.width
        let art = CGRect(x: tile.midX - width / 2, y: tile.midY - height / 2, width: width, height: height)

        ctx.saveGState()
        let scale = fit(artBounds, into: art, ctx)
        let stroke = max(strokeWidth, thinnest / scale)

        if detailed {
            drawDebossed(in: ctx, stroke: stroke)
        } else {
            ctx.setStrokeColor(Palette.stroke)
            strokeOutline(in: ctx, width: stroke)
        }
        drawLight(in: ctx, lineWidth: max(lightWidth, thinnest / scale), pixel: scale)
        ctx.restoreGState()
    }

    // MARK: - Menu-bar glyph

    /// Draws the logo in black for a template image, fitted inside `rect`.
    /// Unlit, it's the laptop's outline; `lit` adds the cone of light under
    /// the lid, like the filled variant of an SF Symbol.
    ///
    /// `stroke` is in `rect`'s units: menu-bar glyphs need a heavier line
    /// than the artwork's, which would vanish at this size.
    public static func drawGlyph(in ctx: CGContext, rect: CGRect, lit: Bool, stroke: CGFloat = 1.15) {
        ctx.saveGState()
        // Fit the outline's centre line, leaving room for the stroke round it.
        let scale = fit(glyphBounds, into: rect.insetBy(dx: stroke / 2, dy: stroke / 2), ctx)
        let width = stroke / scale

        if lit {
            ctx.saveGState()
            ctx.addPath(cone())
            ctx.clip()
            let n = towardBase
            ctx.drawLinearGradient(
                gradient([(0, gray(0, 0.8)), (0.35, gray(0, 0.42)), (1, gray(0, 0.12))]),
                start: lightStart, end: lightStart + n * 150, options: [.drawsAfterEndLocation]
            )
            ctx.restoreGState()
        }

        ctx.setStrokeColor(gray(0, 1))
        strokeOutline(in: ctx, width: width)
        ctx.restoreGState()
    }

    // MARK: - Geometry (artwork pixels, y down)

    /// The outline's stroke width in the artwork.
    static let strokeWidth: CGFloat = 7.5

    /// Where the lid's underside meets the base.
    static let hinge = CGPoint(x: 261.6, y: 353)

    /// The base's top edge, which the lid closes onto.
    static let baseTop: CGFloat = 353

    /// The screen's light: a bright line just under the lid…
    static let lightStart = CGPoint(x: 289, y: 351.4)
    static let lightEnd = CGPoint(x: 674, y: 184.2)
    static let lightWidth: CGFloat = 7

    /// …and the cone it casts down to the base. It ends in a soft rounded
    /// edge: part of this ellipse, which takes in the whole cone so the
    /// edge can fade along it.
    static let coneEdge = CGRect(x: 300 - 490, y: 300 - 285, width: 980, height: 570)

    /// Everything the icon draws, cone included.
    static let artBounds = CGRect(x: 238, y: 136, width: 558, height: 260)

    /// The glyph's extent: the outline's centre line, and the cone, which
    /// reaches a little past the base. Lit or not, the glyph keeps this
    /// layout, so it doesn't shift when the light comes on.
    static let glyphBounds = CGRect(x: 246.5, y: 144.2, width: 543.5, height: 242.3)

    /// The two ports on the base's side.
    static let ports = [
        CGRect(x: 277.5, y: 367, width: 30.5, height: 8),
        CGRect(x: 323, y: 367, width: 31.4, height: 8),
    ]

    /// The laptop's outline: one loop round lid and base, which meet at the
    /// hinge, plus the short stretch of the base's top edge inside the left
    /// end.
    static func outline() -> CGPath {
        let path = CGMutablePath()
        path.move(to: hinge)
        // The lid's underside, up to its rounded tip…
        path.addLine(to: CGPoint(x: 708, y: 163.6))
        path.addCurve(to: CGPoint(x: 722.5, y: 153.5),
                      control1: CGPoint(x: 714, y: 161.1), control2: CGPoint(x: 722.5, y: 159.5))
        path.addCurve(to: CGPoint(x: 711.5, y: 144.2),
                      control1: CGPoint(x: 722.5, y: 148), control2: CGPoint(x: 717, y: 144.2))
        // …back along its top, which flattens toward the tip…
        path.addQuadCurve(to: CGPoint(x: 600, y: 176), control: CGPoint(x: 670.4, y: 144.2))
        path.addLine(to: CGPoint(x: 300, y: 311.5))
        // …and round the left end to the base's underside.
        path.addCurve(to: CGPoint(x: 246.5, y: 352),
                      control1: CGPoint(x: 270.8, y: 324.7), control2: CGPoint(x: 246.5, y: 338))
        path.addLine(to: CGPoint(x: 246.5, y: 360))
        path.addCurve(to: CGPoint(x: 276.5, y: 386.5),
                      control1: CGPoint(x: 246.5, y: 378.5), control2: CGPoint(x: 258.5, y: 386.5))
        path.addLine(to: CGPoint(x: 727, y: 386.5))
        // The base's front sweeps up into a nearly square corner.
        path.addCurve(to: CGPoint(x: 777, y: 359.5),
                      control1: CGPoint(x: 754.6, y: 386.5), control2: CGPoint(x: 777, y: 374.4))
        path.addLine(to: CGPoint(x: 777, y: 356.5))
        path.addQuadCurve(to: CGPoint(x: 773.5, y: baseTop), control: CGPoint(x: 777, y: baseTop))
        path.closeSubpath() // the base's top edge, back to the hinge

        path.move(to: CGPoint(x: 246.5, y: baseTop))
        path.addLine(to: hinge)
        return path
    }

    /// Down the light line, perpendicular to it, toward the base.
    static var towardBase: CGPoint {
        let d = unit(lightEnd - lightStart)
        return CGPoint(x: -d.y, y: d.x)
    }

    /// The region the screen lights: under the light line, above the base,
    /// out to the edge ellipse.
    static func cone() -> CGPath {
        // Work on the edge ellipse as a unit circle.
        let rx = coneEdge.width / 2, ry = coneEdge.height / 2
        let toCircle = CGAffineTransform(scaleX: 1 / rx, y: 1 / ry)
            .translatedBy(x: -coneEdge.midX, y: -coneEdge.midY)
        let p = lightStart.applying(toCircle)
        let d = unit(lightEnd - lightStart)
        let v = CGPoint(x: d.x / rx, y: d.y / ry)

        // Where the light line, carried on, leaves the ellipse…
        let a = v.x * v.x + v.y * v.y
        let b = p.x * v.x + p.y * v.y
        let c = p.x * p.x + p.y * p.y - 1
        let t = (-b + (b * b - a * c).squareRoot()) / a
        let corner = (p + v * t)
        // …and where the ellipse comes down to the base.
        let floor = asin((baseTop - coneEdge.midY) / ry)

        let path = CGMutablePath()
        path.move(to: lightStart)
        path.addArc(center: .zero, radius: 1, startAngle: atan2(corner.y, corner.x), endAngle: floor,
                    clockwise: false, transform: toCircle.inverted())
        path.addLine(to: CGPoint(x: lightStart.x, y: baseTop))
        path.closeSubpath()
        return path
    }

    /// Draws a radial gradient stretched to the cone's edge ellipse, so its
    /// locations run from the ellipse's centre (0) to its edge (1).
    private static func drawEdgeGradient(_ gradient: CGGradient, in ctx: CGContext, extend: Bool) {
        ctx.saveGState()
        ctx.translateBy(x: coneEdge.midX, y: coneEdge.midY)
        ctx.scaleBy(x: 1, y: coneEdge.height / coneEdge.width)
        ctx.drawRadialGradient(
            gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: coneEdge.width / 2,
            options: extend ? [.drawsBeforeStartLocation, .drawsAfterEndLocation] : []
        )
        ctx.restoreGState()
    }

    // MARK: - Drawing

    private enum Palette {
        static let stroke = rgb(60, 62, 67)
        static let strokeShade = rgb(30, 32, 37, 0.8)
        static let highlight = gray(1, 0.27)
        static let port = rgb(50, 53, 58)
        static let light = rgb(52, 245, 253)
        static let tileTop = rgb(163, 162, 168)
        static let tileBottom = rgb(66, 65, 71)
    }

    /// Maps artwork coordinates (y down) into `rect` (y up), keeping the
    /// aspect ratio. Returns the scale, in `rect` units per artwork pixel.
    private static func fit(_ bounds: CGRect, into rect: CGRect, _ ctx: CGContext) -> CGFloat {
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        ctx.translateBy(x: rect.midX, y: rect.midY)
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -bounds.midX, y: -bounds.midY)
        return scale
    }

    private static func strokeOutline(in ctx: CGContext, width: CGFloat) {
        ctx.addPath(outline())
        ctx.setLineWidth(width)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.strokePath()
    }

    /// The artwork's pressed-in look: a dark line with a darker top edge,
    /// over a sliver of highlight that shows just beneath it.
    private static func drawDebossed(in ctx: CGContext, stroke: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: 2.4)
        ctx.setStrokeColor(Palette.highlight)
        strokeOutline(in: ctx, width: stroke)
        ctx.setFillColor(Palette.highlight)
        for port in ports { ctx.addPath(CGPath(roundedRect: port, cornerWidth: 4, cornerHeight: 4, transform: nil)) }
        ctx.fillPath()
        ctx.restoreGState()

        ctx.setStrokeColor(Palette.stroke)
        strokeOutline(in: ctx, width: stroke)

        // The darker top edge, kept inside the line itself.
        ctx.saveGState()
        ctx.addPath(outline().copy(strokingWithWidth: stroke, lineCap: .round, lineJoin: .round, miterLimit: 10))
        ctx.clip()
        ctx.translateBy(x: 0, y: -stroke * 0.3)
        ctx.setStrokeColor(Palette.strokeShade)
        strokeOutline(in: ctx, width: stroke * 0.16)
        ctx.restoreGState()

        ctx.setFillColor(Palette.port)
        for port in ports { ctx.addPath(CGPath(roundedRect: port, cornerWidth: 4, cornerHeight: 4, transform: nil)) }
        ctx.fillPath()
    }

    /// The screen's light, in colour: the cone, then the glow round the
    /// light line, then the line itself. `pixel` is device pixels per
    /// artwork pixel, for the shadow that blooms the line.
    private static func drawLight(in ctx: CGContext, lineWidth: CGFloat, pixel: CGFloat) {
        let n = towardBase
        let cyan = { (alpha: CGFloat) in rgb(50, 247, 255, alpha) }

        // The cone: brightest under the lid and fading toward the base, but
        // growing stronger toward its rounded edge, where a band of light
        // runs all the way down before the edge itself fades out.
        let opaque = { (alpha: CGFloat) in gray(0, alpha) }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(cone())
        ctx.clip()
        ctx.drawLinearGradient(
            gradient([(0, cyan(0.26)), (0.3, cyan(0.24)), (0.475, cyan(0.18)), (0.625, cyan(0.09)),
                      (0.825, cyan(0.045)), (1, cyan(0))]),
            start: lightStart, end: lightStart + n * 200, options: [.drawsAfterEndLocation]
        )
        ctx.setBlendMode(.destinationIn)
        drawEdgeGradient(gradient([(0.5, opaque(0.55)), (0.7, opaque(0.65)), (0.85, opaque(0.85)), (0.95, opaque(1))]),
                         in: ctx, extend: true)
        ctx.setBlendMode(.normal)
        drawEdgeGradient(gradient([(0.72, cyan(0)), (0.86, cyan(0.07)), (0.92, cyan(0.09)), (1, cyan(0.09))]),
                         in: ctx, extend: false)
        ctx.setBlendMode(.destinationIn)
        drawEdgeGradient(gradient([(0.92, opaque(1)), (1, opaque(0))]), in: ctx, extend: true)
        ctx.endTransparencyLayer()

        // The glow round the line, wider below it than above. It spills a
        // little into the base by the hinge, so it fades in there rather than
        // stopping at an edge, and fades out short of the lid's tip.
        let length = hypot(lightEnd.x - lightStart.x, lightEnd.y - lightStart.y)
        let above: CGFloat = 40, below: CGFloat = 60
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let glow: [(CGFloat, CGFloat)] = [
            (-40, 0), (-20, 0.06), (-10, 0.2), (-4, 0.42), (0, 0.48), (4, 0.46),
            (10, 0.41), (20, 0.29), (30, 0.16), (40, 0.07), (50, 0.02), (60, 0),
        ]
        ctx.drawLinearGradient(
            gradient(glow.map { ((above + $0.0) / (above + below), cyan($0.1)) }),
            start: lightStart - n * above, end: lightStart + n * below, options: []
        )
        fadeAlongLight(in: ctx, from: -30, fullFrom: 10, fullTo: length - 30, to: length + 25)
        ctx.endTransparencyLayer()

        // The line itself, which starts where it meets the base's top edge.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: 2000, height: baseTop - strokeWidth / 2))
        ctx.setShadow(offset: .zero, blur: 10 * pixel, color: cyan(0.9))
        ctx.setStrokeColor(Palette.light)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.move(to: lightStart)
        ctx.addLine(to: lightEnd)
        ctx.strokePath()
        ctx.restoreGState()
        fadeAlongLight(in: ctx, from: -1, fullFrom: 0, fullTo: length - 30, to: length + 25)
        ctx.endTransparencyLayer()
    }

    /// Masks what's been drawn so far in the current transparency layer
    /// along the light line: clear before `from` and after `to`, full
    /// strength from `fullFrom` to `fullTo`. Distances are along the line
    /// from its start.
    private static func fadeAlongLight(in ctx: CGContext, from: CGFloat, fullFrom: CGFloat,
                                       fullTo: CGFloat, to: CGFloat) {
        let d = unit(lightEnd - lightStart)
        let span = to - from
        ctx.saveGState()
        ctx.setBlendMode(.destinationIn)
        ctx.drawLinearGradient(
            gradient([
                (0, gray(0, 0)), ((fullFrom - from) / span, gray(0, 1)),
                ((fullTo - from) / span, gray(0, 1)), (1, gray(0, 0)),
            ]),
            start: lightStart + d * from, end: lightStart + d * to,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        ctx.restoreGState()
    }

    /// The icon's tile: the macOS rounded square, lit from above, with a
    /// fine grain, a soft edge, and a shadow beneath.
    private static func drawTile(in ctx: CGContext, rect: CGRect, unit: CGFloat, detailed: Bool) {
        let shape = squircle(in: rect)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 20 * unit, color: gray(0, 0.3))
        ctx.addPath(shape)
        ctx.setFillColor(Palette.tileBottom)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.drawLinearGradient(
            gradient([(0, Palette.tileTop), (1, Palette.tileBottom)]),
            start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: []
        )
        let top = CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.1)
        ctx.drawRadialGradient(
            gradient([(0, gray(1, 0.12)), (1, gray(1, 0))]),
            startCenter: top, startRadius: 0, endCenter: top, endRadius: rect.width * 0.75, options: []
        )
        let middle = CGPoint(x: rect.midX, y: rect.midY)
        ctx.drawRadialGradient(
            gradient([(0.45, gray(0, 0)), (1, gray(0, 0.14))]),
            startCenter: middle, startRadius: 0, endCenter: middle, endRadius: rect.width * 0.72,
            options: [.drawsAfterEndLocation]
        )
        if detailed, let grain = grain(side: Int(rect.width.rounded())) {
            ctx.setAlpha(0.045)
            ctx.draw(grain, in: rect)
            ctx.setAlpha(1)
        }

        // A lighter top edge and a darker bottom one, inside the tile.
        ctx.addPath(shape)
        ctx.setLineWidth(max(3 * unit, 1))
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(
            gradient([(0, gray(1, 0.28)), (0.5, gray(1, 0.04)), (1, gray(0, 0.2))]),
            start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: []
        )
        ctx.restoreGState()
    }

    /// The macOS icon shape, approximated by a superellipse (n = 5).
    private static func squircle(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let a = rect.width / 2, b = rect.height / 2
        let steps = 720
        for i in 0..<steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let c = cos(t), s = sin(t)
            let x = rect.midX + a * copysign(pow(abs(c), 2 / 5), c)
            let y = rect.midY + b * copysign(pow(abs(s), 2 / 5), s)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }

    /// Monochrome noise, the same every time, so builds are reproducible.
    private static func grain(side: Int) -> CGImage? {
        guard side > 0 else { return nil }
        var state: UInt64 = 0x4C69_644B_6565_7072 // "LidKeepr"
        var bytes = [UInt8](repeating: 0, count: side * side)
        for i in bytes.indices {
            // SplitMix64.
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            bytes[i] = UInt8(truncatingIfNeeded: z ^ (z >> 31))
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: - Helpers

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: sRGB, components: [r / 255, g / 255, b / 255, a])!
    }

    private static func gray(_ white: CGFloat, _ alpha: CGFloat) -> CGColor {
        CGColor(colorSpace: sRGB, components: [white, white, white, alpha])!
    }

    private static func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
        CGGradient(colorsSpace: sRGB, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
    }

    private static func unit(_ v: CGPoint) -> CGPoint {
        let length = hypot(v.x, v.y)
        return CGPoint(x: v.x / length, y: v.y / length)
    }
}

private func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
private func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
private func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
