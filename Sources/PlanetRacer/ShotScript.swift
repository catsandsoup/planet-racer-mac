import AppKit
import ImageIO
import PlanetRacerCore
import MetalKit
import SwiftUI
import UniformTypeIdentifiers

/// Developer-only: PLANETRACER_SHOTS=<dir> walks the player journey and saves real frames
/// (Metal game view + SwiftUI overlay composited), then quits. Players never see this.
enum ShotScript {
    static let dir = ProcessInfo.processInfo.environment["PLANETRACER_SHOTS"]
    static var enabled: Bool { dir != nil }
    static var pendingCapture: String?

    static func step(_ m: GameModel) {
        let f = m.frameCount
        let race = 36 * 6 // ~6 s of racing at 60 fps
        switch f {
        case 60:
            if ProcessInfo.processInfo.environment["PLANETRACER_SHOT_MOD"] != nil {
                m.go(.mods, focus: 0)
                pendingCapture = "1_mods.png"
            } else { pendingCapture = "1_title.png" }
        case 61:
            if let name = ProcessInfo.processInfo.environment["PLANETRACER_SHOT_MOD"],
               let mod = BundledMod(rawValue: name) { m.openMod(mod) }
            else { m.titleEntries.first { $0.0 == "QUICK RACE" }?.1() }
        case 100: pendingCapture = "2_quickrace.png"
        case 101: m.startRace()
        case 140: pendingCapture = "3_race_start.png"
        case 141: m.autopilot = true; if let g = m.game { pr_race_start(g) }
        case 141 + race: pendingCapture = "4_racing.png"
        case 142 + race: m.pause()
        case 170 + race: pendingCapture = "5_pause.png"
        case 171 + race: m.activate(.pause, 2)
        case 200 + race: pendingCapture = "6_settings.png"
        case 201 + race: m.phase = .playing; m.settings.framing = .original
        case 240 + race: pendingCapture = "7_original_framing.png"
        case 241 + race: m.settings.framing = .widescreen
        case 241 + race * 3: pendingCapture = "8_later.png"
        case 242 + race * 3: m.settings.framing = .widescreen; m.autopilot = false; m.quitRace(to: .title); stage = 1; wait = f + 30
        default: if stage > 0 && f >= wait { career(m, f) }
        }
    }

    // The career journey: new career, garage, shop, planets, travel, a rival, a race, results, home, load.
    static var stage = 0
    static var wait = 0
    private static func next(_ f: Int, _ frames: Int = 30) { stage += 1; wait = f + frames }

    private static func career(_ m: GameModel, _ f: Int) {
        guard let g = m.game else { return }
        switch stage {
        case 1: m.newCareer(); m.nameEntry = "Zoot"; next(f)
        case 2: pendingCapture = "9_new_career.png"; next(f, 2)
        case 3: m.startNewCareer(); next(f)
        case 4: pendingCapture = "10_garage.png"; next(f, 2)
        case 5: m.activate(.garage, 5); next(f)
        case 6: pendingCapture = "11_shop.png"; next(f, 2)
        case 7: // the race chassis in the buy dialog
            let rows = m.shopRows()
            let i = rows.lastIndex { $0.kind == Int32(PR_CHASSIS) && $0.enabled } ?? 3
            m.focus = i + 1; m.activate(.shop, i + 1); m.dialog?.selector?.change(4); next(f)
        case 8: pendingCapture = "12_shop_buy.png"; next(f, 2)
        case 9: m.back(.dialog); m.shopTab = 1; m.focus = 1; next(f)
        case 10: pendingCapture = "13_shop_sell.png"; next(f, 2)
        case 11: m.activate(.garage, 4); m.go(.planets, focus: 2); next(f)
        case 12: pendingCapture = "14_planets.png"; next(f, 2)
        case 13: m.activate(.planets, 2); next(f)
        case 14: pendingCapture = "15_travel.png"; next(f, 2)
        case 15: m.activate(.dialog, m.items(.dialog).count - 2); next(f) // OK
        case 16: // let rivals pull up until one makes a money offer
            for _ in 0..<30 where m.encounter.state != Int32(PR_ENC_OFFER) || m.encounter.initialAmount <= 4 {
                if m.career.planet == 0 { break }
                pr_career_continue(g)
                if m.encounter.state == Int32(PR_ENC_REFUSED) { pr_career_refusal_elapsed(g) }
            }
            m.careerRev += 1; m.focus = m.defaultRivalFocus(); next(f)
        case 17: pendingCapture = "16_rival.png"; next(f, 2)
        case 18: m.change(.rival, 0, -1); m.change(.rival, 0, -1); m.focus = 2; next(f)
        case 19: pendingCapture = "17_rival_negotiate.png"; next(f, 2)
        case 20:
            for _ in 0..<40 where m.screen != .race {
                if m.career.planet == 0 { break }
                let e = m.encounter
                if e.state == Int32(PR_ENC_OFFER) || e.state == Int32(PR_ENC_ACCEPTED) {
                    if e.negotiating { pr_career_adjust_amount(g, e.amount < e.initialAmount ? 1 : -1); continue }
                    if pr_career_accept(g) { m.startCareerRace() }
                } else { pr_career_continue(g); if m.encounter.state == Int32(PR_ENC_REFUSED) { pr_career_refusal_elapsed(g) } }
            }
            next(f, 40)
        case 21: m.autopilot = true; pr_race_start(g); next(f, 36 * 4)
        case 22: pendingCapture = "18_career_race.png"; next(f, 2)
        case 23: if m.phase == .results || f > wait + 60 * 120 { m.autopilot = false; next(f, 30) }
        case 24: pendingCapture = "19_career_results.png"; next(f, 2)
        case 25: m.resultsShownAt = -1; m.activate(.results, 0); next(f)
        case 26: pendingCapture = "20_after_race.png"; next(f, 2)
        case 27:
            if m.screen == .rival { m.activate(.rival, m.items(.rival).count - 1) } // GO HOME
            m.dialog = nil; next(f)
        case 28: pendingCapture = "21_garage_after.png"; next(f, 2)
        case 29: m.go(.instructions); next(f)
        case 30: pendingCapture = "22_instructions.png"; next(f, 2)
        case 31: m.go(.title, focus: 0); m.go(.loadCareer, focus: 0); next(f)
        case 32: pendingCapture = "23_load.png"; next(f, 2)
        case 33: m.go(.title, focus: 0); next(f)
        case 34: pendingCapture = "24_title_continue.png"; next(f, 2)
        case 35: // challenge the King: give the throwaway career the $100,000 fee
            var json = String(cString: pr_career_to_json(g))
            if let r = json.range(of: #""cash": \d+"#, options: .regularExpression) { json.replaceSubrange(r, with: "\"cash\": 250000") }
            _ = pr_career_load_json(g, json)
            if pr_career_travel(g, 5) == Int32(PR_OK) { m.careerRev += 1; m.go(.rival, focus: m.defaultRivalFocus()) }
            next(f)
        case 36: pendingCapture = "25_rival_king.png"; next(f, 2)
        case 37: m.save(); NSApp.terminate(nil)
        default: break
        }
    }

    /// Reads the frame back, renders the SwiftUI overlay offscreen, composites both into a PNG.
    static func capture(name: String, drawable d: CAMetalDrawable, commandBuffer cb: MTLCommandBuffer, view: MTKView, model: GameModel) {
        guard let dir else { return }
        let drawable = d.texture
        let w = drawable.width, h = drawable.height
        let bytesPerRow = w * 4
        guard let buf = cb.device.makeBuffer(length: bytesPerRow * h, options: .storageModeShared),
              let blit = cb.makeBlitCommandEncoder() else { return }
        blit.copy(from: drawable, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                  sourceSize: MTLSize(width: w, height: h, depth: 1), to: buf, destinationOffset: 0,
                  destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerRow * h)
        blit.endEncoding()
        cb.present(d)
        cb.commit()
        cb.waitUntilCompleted()

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let provider = CGDataProvider(data: Data(bytes: buf.contents(), count: bytesPerRow * h) as CFData),
              let game = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: cs,
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return }
        ctx.draw(game, in: CGRect(x: 0, y: 0, width: w, height: h))

        let size = view.bounds.size
        let overlay: CGImage? = MainActor.assumeIsolated {
            let renderer = ImageRenderer(content: OverlayView(model: model).frame(width: size.width, height: size.height))
            renderer.scale = CGFloat(w) / size.width
            return renderer.cgImage
        }
        if let overlay { ctx.draw(overlay, in: CGRect(x: 0, y: 0, width: w, height: h)) }

        guard let out = ctx.makeImage() else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
        if let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, out, nil)
            CGImageDestinationFinalize(dest)
        }
    }
}

