import CoreGraphics
import PlanetRacerCore
import simd

/// Where the race is drawn inside the window. Units: whatever the caller passes (points or pixels).
struct ViewLayout {
    var rect: CGRect      // the game view (pillarboxed for Original framing)
    var scale: CGFloat    // per game unit; the view is always 400 game units tall
    var widthUnits: CGFloat { rect.width / scale }

    init(size: CGSize, framing: Framing) {
        var s = size.height / 400
        if framing == .original {
            if 550 * s > size.width { s = size.width / 550 }
            rect = CGRect(x: (size.width - 550 * s) / 2, y: (size.height - 400 * s) / 2, width: 550 * s, height: 400 * s)
        } else {
            rect = CGRect(origin: .zero, size: size)
        }
        scale = s
    }
}

/// HUD positions in game units from the view's top-left (shared by Metal and the SwiftUI text layer).
enum HudLayout {
    static let dial = CGPoint(x: 52, y: 50), dialRadius: CGFloat = 36
    static let barWidth: CGFloat = 120
    static func fuelBar(_ w: CGFloat) -> CGRect { CGRect(x: w / 2 - barWidth / 2, y: 10, width: barWidth, height: 8) }
    static func impactBar(_ w: CGFloat) -> CGRect { CGRect(x: w / 2 - barWidth / 2, y: 36, width: barWidth, height: 5) }
}

/// C fixed-size arrays arrive in Swift as tuples; copy them out as arrays.
func cArray<T, E>(_ tuple: T, _: E.Type, count: Int) -> [E] {
    withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: E.self).prefix(count)) }
}

final class RaceRenderer {
    let assets: Assets
    private var segs = [PRSegment](repeating: PRSegment(), count: 512)
    private var stars = [PRStar](repeating: PRStar(), count: 64)
    private var tiles = [PRTile](repeating: PRTile(), count: 16)

    init(assets: Assets) { self.assets = assets }

    private func sprite(_ name: String) -> SpriteImage? { assets.sprites[name] }

    func draw(_ r: Renderer2D, game: OpaquePointer, prev: PRFrame, cur: PRFrame, alpha: Float, tick: Int,
              layout: ViewLayout, planet: PRPlanetInfo) {
        let s = Float(layout.scale)
        let vx = Float(layout.rect.minX), vy = Float(layout.rect.minY)
        let viewW = Float(layout.rect.width) / s, viewH: Float = 400

        r.scissor(layout.rect)
        r.xf = .init()
        // sky (screen-fixed) and stars (drift with slight parallax), like mcBg/mcSter
        if let sky = sprite("scene/sky") { r.image(sky, in: layout.rect) }
        let nStars = Int(pr_race_stars(game, &stars, Int32(stars.count)))
        for st in stars.prefix(nStars) {
            if let img = sprite("scene/star_\(st.frame)") {
                r.image(img, x: vx + Float(st.x) * s, y: vy + Float(st.y) * s, scale: s)
            }
        }

        let camX = Float(prev.camX + (cur.camX - prev.camX) * Double(alpha))
        let camY = Float(prev.camY + (cur.camY - prev.camY) * Double(alpha))
        r.xf = .camera(scale: s, offset: SIMD2(vx, vy), target: SIMD2(camX, camY))

        let size = Float(cur.planetSize)
        if cur.showStartBuildings || camX < 1400 + viewW, let b = sprite("scene/buildings_start") { r.image(b, x: 260, y: 0) }
        if camX > size - 1000 - viewW, let b = sprite("scene/buildings_finish") {
            r.image(b, x: size, y: Float(cur.finishGroundY))
        }

        // ground: fill each visible piece to the bottom of the view, then the 12-unit rim line
        let fill = SIMD4<Float>(rgb: planet.fill), line = SIMD4<Float>(rgb: planet.line)
        let n = Int(pr_race_segments(game, &segs, Int32(segs.count)))
        let bottom = camY + viewH + 20
        let visible = segs.prefix(n).filter { Float($0.x1) >= camX - 20 && Float($0.x0) <= camX + viewW + 20 }
        for g in visible {
            let a = SIMD2(Float(g.x0), Float(g.y0) + 6), b = SIMD2(Float(g.x1), Float(g.y1) + 6)
            r.quad(a, b, SIMD2(b.x, bottom), SIMD2(a.x, bottom), fill)
        }
        for g in visible {
            let a = SIMD2(Float(g.x0), Float(g.y0) + 6), b = SIMD2(Float(g.x1), Float(g.y1) + 6)
            r.line(a, b, width: 12, line)
            r.circle(a, radius: 6, line, segments: 12)
            r.circle(b, radius: 6, line, segments: 12)
        }

        // cars appear once the player presses a key (carsVisible in the original)
        if cur.started {
            let count = Int(cur.pointCount)
            let carPts = lerp(cArray(prev.car, PRPoint.self, count: count), cArray(cur.car, PRPoint.self, count: count), alpha)
            drawCar(r, carPts, frame: cur, opponent: false, chassisArt: Int(cur.chassisArt),
                    color: cur.playerKingmobile ? assets.kingmobileColor : Int(cur.color),
                    tireArt: Int(cur.tireArt), tint: SIMD4(rgb: cur.wheelTint), flame: cur.boosting, struts: !cur.crashed, tick: tick)
            if cur.oppVisible {
                let oppPts = lerp(cArray(prev.opp, PRPoint.self, count: count), cArray(cur.opp, PRPoint.self, count: count), alpha)
                let color = cur.oppKingmobile ? assets.kingmobileColor : Int(cur.oppColor)
                drawCar(r, oppPts, frame: cur, opponent: true, chassisArt: Int(cur.oppChassisArt), color: color,
                        tireArt: Int(cur.oppTireArt), tint: SIMD4(rgb: cur.oppWheelTint), flame: cur.oppBurning, struts: true, tick: tick)
            }
        }

        // ground strata lines. The original calls Color.setRGB(planet.colors.lineColor), but lineColor is the
        // string "0xCECCDD"; Flash coerces that to 0, so the lines render black. Match what players saw.
        let nTiles = Int(pr_race_tiles(game, &tiles, Int32(tiles.count)))
        for t in tiles.prefix(nTiles) {
            if let img = sprite("scene/surface_tile_\(t.frame)") { r.image(img, x: Float(t.x), y: Float(t.y), tint: SIMD4(0, 0, 0, 1)) }
        }
        if let flag = sprite("scene/start_finish") { r.image(flag, x: size, y: Float(cur.finishGroundY)) }

        r.xf = .init()
        drawHud(r, cur, layout: layout)
        r.scissor(nil)
    }

    private func lerp(_ a: [PRPoint], _ b: [PRPoint], _ t: Float) -> [PRPoint] {
        guard a.count == b.count else { return b }
        let td = Double(t)
        var out = b
        for i in b.indices {
            if abs(a[i].x - b[i].x) > 60 || abs(a[i].y - b[i].y) > 60 { return b } // teleported (opponent respawn)
            out[i].x = a[i].x + (b[i].x - a[i].x) * td
            out[i].y = a[i].y + (b[i].y - a[i].y) * td
            out[i].rimX = a[i].rimX + (b[i].rimX - a[i].rimX) * td
            out[i].rimY = a[i].rimY + (b[i].rimY - a[i].rimY) * td
        }
        return out
    }

    private func drawCar(_ r: Renderer2D, _ p: [PRPoint], frame f: PRFrame, opponent: Bool, chassisArt: Int, color: Int,
                         tireArt: Int, tint: SIMD4<Float>, flame: Bool, struts: Bool, tick: Int) {
        guard p.count > 5 else { return }
        func v(_ i: Int) -> SIMD2<Float> { SIMD2(Float(p[i].x), Float(p[i].y)) }
        if struts { // white suspension struts under the wheels (vC.lineStyle(6) in the original)
            r.line(v(3), v(1), width: 6, SIMD4(1, 1, 1, 1))
            r.line(v(2), v(0), width: 6, SIMD4(1, 1, 1, 1))
        }
        for pt in p where pt.wheel {
            let k = Float(pt.r) / assets.wheelArtRadius
            let x = Float(pt.x), y = Float(pt.y)
            let rot = Float(atan2(pt.rimY, pt.rimX) * 180 / .pi)
            if let i = sprite("wheel/under") { r.image(i, x: x, y: y, scale: k) }
            if let i = sprite("wheel/color") { r.image(i, x: x, y: y, scale: k, tint: tint) }
            if let i = sprite("wheel/over") { r.image(i, x: x, y: y, scale: k) }
            if let i = sprite("wheel/tire_\(tireArt)") { r.image(i, x: x, y: y, rotation: rot, scale: k) }
        }
        let idx = cArray(f.bodyIdx, Int32.self, count: Int(f.bodyCount))
        var c = SIMD2<Float>(0, 0)
        for i in idx { c += v(Int(i)) }
        c /= Float(max(1, idx.count))
        let a = v(Int(f.bodyA)), b = v(Int(f.bodyB))
        let rot = atan2(b.y - a.y, b.x - a.x) * 180 / .pi
        let side = opponent ? "car/opponent/" : "car/player/"
        if flame, let i = sprite(side + "flame_\(tick % 5 + 1)") { r.image(i, x: c.x, y: c.y, rotation: rot) }
        if let i = sprite(side + "exhaust_t\(chassisArt)") { r.image(i, x: c.x, y: c.y, rotation: rot) }
        if let i = sprite(side + "body_t\(chassisArt)_c\(color)") { r.image(i, x: c.x, y: c.y, rotation: rot) }
    }

    /// HUD graphics (the text is SwiftUI, see HudOverlay): planet dial, afterburner fuel, impact flash.
    private func drawHud(_ r: Renderer2D, _ f: PRFrame, layout: ViewLayout) {
        let s = Float(layout.scale)
        let o = SIMD2(Float(layout.rect.minX), Float(layout.rect.minY))
        func P(_ x: CGFloat, _ y: CGFloat) -> SIMD2<Float> { o + SIMD2(Float(x), Float(y)) * s }
        let yellow = SIMD4<Float>(1, 1, 0, 1)
        let c = P(HudLayout.dial.x, HudLayout.dial.y), rad = Float(HudLayout.dialRadius) * s
        r.ring(c, inner: rad - 1.6 * s, outer: rad + 1.6 * s, yellow)
        // you go clockwise, the opponent anticlockwise; you meet at the bottom (the finish)
        func marker(_ progress: Double, clockwise: Bool, _ col: SIMD4<Float>) {
            let sign: Double = clockwise ? 1 : -1
            let deg: Double = -90 + sign * 180 * min(1, max(0, progress))
            let a = Float(deg * Double.pi / 180)
            let p: SIMD2<Float> = c + SIMD2<Float>(cos(a), sin(a)) * rad
            r.circle(p, radius: 6 * s, SIMD4(0, 0, 0, 1))
            r.circle(p, radius: 4.8 * s, col)
        }
        marker(f.oppProgress, clockwise: false, SIMD4(0.9, 0.2, 0.15, 1))
        marker(f.playerProgress, clockwise: true, yellow)

        func bar(_ rc: CGRect, _ frac: Double, _ col: SIMD4<Float>) {
            let x = Float(layout.rect.minX + rc.minX * layout.scale), y = Float(layout.rect.minY + rc.minY * layout.scale)
            let w = Float(rc.width) * s, h = Float(rc.height) * s
            r.rect(x - s, y - s, w + 2 * s, h + 2 * s, SIMD4(0.8, 0.8, 0.8, 0.6))
            r.rect(x, y, w, h, SIMD4(0.08, 0.08, 0.11, 0.9))
            let fw: Float = w * Float(min(1, max(0, frac)))
            let lighter: SIMD4<Float> = col + SIMD4<Float>(repeating: 0.35)
            let top: SIMD4<Float> = simd_min(lighter, SIMD4<Float>(repeating: 1))
            r.gradientRectV(x, y, fw, h, top: top, bottom: col)
        }
        let w = layout.widthUnits
        bar(HudLayout.fuelBar(w), f.boostFraction, SIMD4(0.27, 0.59, 1, 1))
        bar(HudLayout.impactBar(w), f.damageFlash / 100, SIMD4(0.9, 0.2, 0.15, 1))
    }
}
