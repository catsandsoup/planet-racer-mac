import MetalKit
import PlanetRacerCore
import SwiftUI

/// Hosts the MTKView. Its draw callback is the game loop: one model update + one render per
/// display refresh (60 Hz, or 120 Hz on ProMotion displays).
struct MetalView: NSViewRepresentable {
    let model: GameModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        v.colorPixelFormat = .bgra8Unorm
        v.sampleCount = Renderer2D.sampleCount
        v.preferredFramesPerSecond = 120
        v.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        v.framebufferOnly = ShotScript.enabled == false // the screenshot journey reads frames back
        v.delegate = context.coordinator
        context.coordinator.setup(v)
        return v
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}

    final class Coordinator: NSObject, MTKViewDelegate {
        let model: GameModel
        var renderer: Renderer2D?
        var race: RaceRenderer?
        var last = CACurrentMediaTime()

        init(model: GameModel) { self.model = model }

        func setup(_ v: MTKView) {
            guard let dev = v.device else { model.errorText = "This Mac has no Metal GPU."; model.screen = .error; return }
            model.load(device: dev)
            renderer = try? Renderer2D(device: dev, pixelFormat: v.colorPixelFormat)
            if let a = model.assets {
                race = RaceRenderer(assets: a)
                Fonts.ui = a.uiFontName
                Fonts.numbers = a.numberFontName
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            let now = CACurrentMediaTime()
            let dt = min(now - last, 0.25)
            last = now
            let focused = ShotScript.enabled || ((view.window?.isKeyWindow ?? false) && NSApp.isActive)
            model.update(dt: dt, viewSize: view.bounds.size, windowFocused: focused)

            guard let r = renderer, let rp = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
                  let cb = r.queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
            let px = view.drawableSize
            r.begin(enc, size: SIMD2(Float(px.width), Float(px.height)))
            if model.screen == .race, let g = model.game, let race {
                let layout = ViewLayout(size: px, framing: model.settings.framing)
                race.draw(r, game: g, prev: model.prevFrame, cur: model.frame, alpha: model.renderAlpha,
                          tick: model.tickCount, layout: layout, planet: pr_planet(g, pr_race_planet_index(g)))
            }
            r.end()
            enc.endEncoding()
            if ShotScript.enabled, let name = ShotScript.pendingCapture {
                ShotScript.pendingCapture = nil
                ShotScript.capture(name: name, drawable: drawable, commandBuffer: cb, view: view, model: model)
            } else {
                cb.present(drawable)
                cb.commit()
            }
        }
    }
}
