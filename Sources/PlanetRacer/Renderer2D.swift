import Metal
import MetalKit
import simd

/// A small batched 2D renderer on Metal: textured quads (sprites) and flat shapes, in pixel space,
/// with a current affine transform so the game can draw in world units.
final class Renderer2D {
    struct Vertex { var pos: SIMD2<Float>; var uv: SIMD2<Float>; var color: SIMD4<Float> }

    /// 2D affine transform: p' = (a*x + c*y + tx, b*x + d*y + ty)
    struct Affine {
        var a: Float = 1, b: Float = 0, c: Float = 0, d: Float = 1, tx: Float = 0, ty: Float = 0
        func apply(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty) }
        static func camera(scale s: Float, offset: SIMD2<Float>, target: SIMD2<Float>) -> Affine {
            Affine(a: s, b: 0, c: 0, d: s, tx: offset.x - target.x * s, ty: offset.y - target.y * s)
        }
    }

    static let sampleCount = 4
    let device: MTLDevice
    let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let white: MTLTexture
    private var vertices: [Vertex] = []
    private var texture: MTLTexture?
    private var encoder: MTLRenderCommandEncoder?
    private var viewport = SIMD2<Float>(1, 1)
    var xf = Affine()

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float2 pos; float2 uv; float4 color; };
    struct Out { float4 position [[position]]; float2 uv; float4 color; };
    vertex Out vmain(const device Vertex* v [[buffer(0)]], constant float2& size [[buffer(1)]], uint id [[vertex_id]]) {
        Out o;
        float2 p = v[id].pos / size * 2.0 - 1.0;
        o.position = float4(p.x, -p.y, 0, 1);
        o.uv = v[id].uv;
        o.color = v[id].color;
        return o;
    }
    fragment float4 fmain(Out in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]]) {
        return t.sample(s, in.uv) * in.color;
    }
    """

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        self.device = device
        queue = device.makeCommandQueue()!
        let lib = try device.makeLibrary(source: Renderer2D.shaderSource, options: nil)
        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = lib.makeFunction(name: "vmain")
        pd.fragmentFunction = lib.makeFunction(name: "fmain")
        pd.rasterSampleCount = Renderer2D.sampleCount
        let ca = pd.colorAttachments[0]!
        ca.pixelFormat = pixelFormat
        ca.isBlendingEnabled = true // straight (non-premultiplied) alpha, like Flash
        ca.sourceRGBBlendFactor = .sourceAlpha
        ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
        ca.sourceAlphaBlendFactor = .one
        ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try device.makeRenderPipelineState(descriptor: pd)
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear; sd.magFilter = .linear; sd.mipFilter = .linear
        sd.sAddressMode = .clampToEdge; sd.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: sd)!
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        white = device.makeTexture(descriptor: td)!
        var px: UInt32 = 0xFFFF_FFFF
        white.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &px, bytesPerRow: 4)
    }

    func begin(_ enc: MTLRenderCommandEncoder, size: SIMD2<Float>) {
        encoder = enc
        viewport = size
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentSamplerState(sampler, index: 0)
        xf = Affine()
        texture = nil
    }

    func end() {
        flush()
        encoder = nil
    }

    func flush() {
        guard let enc = encoder, !vertices.isEmpty else { return }
        let bytes = vertices.count * MemoryLayout<Vertex>.stride
        if bytes <= 4096 {
            vertices.withUnsafeBytes { enc.setVertexBytes($0.baseAddress!, length: bytes, index: 0) }
        } else {
            guard let buf = device.makeBuffer(bytes: vertices, length: bytes, options: .storageModeShared) else { return }
            enc.setVertexBuffer(buf, offset: 0, index: 0)
        }
        var size = viewport
        enc.setVertexBytes(&size, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        enc.setFragmentTexture(texture ?? white, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        vertices.removeAll(keepingCapacity: true)
    }

    /// Restrict drawing to a pixel rectangle (nil = whole target).
    func scissor(_ r: CGRect?) {
        flush()
        guard let enc = encoder else { return }
        let full = CGRect(x: 0, y: 0, width: CGFloat(viewport.x), height: CGFloat(viewport.y))
        let c = (r ?? full).intersection(full)
        enc.setScissorRect(MTLScissorRect(x: Int(c.minX.rounded()), y: Int(c.minY.rounded()),
                                          width: max(1, Int(c.width.rounded())), height: max(1, Int(c.height.rounded()))))
    }

    private func use(_ t: MTLTexture?) {
        if t !== texture { flush(); texture = t }
    }

    @inline(__always) private func push(_ p: SIMD2<Float>, _ uv: SIMD2<Float>, _ c: SIMD4<Float>) {
        vertices.append(Vertex(pos: xf.apply(p), uv: uv, color: c))
    }

    // MARK: shapes (in the current transform's units)

    func triangle(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>, _ color: SIMD4<Float>) {
        use(nil)
        let uv = SIMD2<Float>(0.5, 0.5)
        push(a, uv, color); push(b, uv, color); push(c, uv, color)
    }

    func quad(_ p0: SIMD2<Float>, _ p1: SIMD2<Float>, _ p2: SIMD2<Float>, _ p3: SIMD2<Float>, _ color: SIMD4<Float>) {
        triangle(p0, p1, p2, color)
        triangle(p0, p2, p3, color)
    }

    func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ color: SIMD4<Float>) {
        quad(SIMD2(x, y), SIMD2(x + w, y), SIMD2(x + w, y + h), SIMD2(x, y + h), color)
    }

    func gradientRectV(_ x: Float, _ y: Float, _ w: Float, _ h: Float, top: SIMD4<Float>, bottom: SIMD4<Float>) {
        use(nil)
        let uv = SIMD2<Float>(0.5, 0.5)
        let a = SIMD2(x, y), b = SIMD2(x + w, y), c = SIMD2(x + w, y + h), d = SIMD2(x, y + h)
        push(a, uv, top); push(b, uv, top); push(c, uv, bottom)
        push(a, uv, top); push(c, uv, bottom); push(d, uv, bottom)
    }

    func line(_ a: SIMD2<Float>, _ b: SIMD2<Float>, width: Float, _ color: SIMD4<Float>) {
        let d = b - a
        let len = simd_length(d)
        guard len > 0.0001 else { return }
        let n = SIMD2(-d.y, d.x) / len * (width / 2)
        quad(a + n, b + n, b - n, a - n, color)
    }

    func circle(_ c: SIMD2<Float>, radius r: Float, _ color: SIMD4<Float>, segments: Int = 24) {
        var prev = c + SIMD2(r, 0)
        for i in 1...segments {
            let t = Float(i) / Float(segments) * 2 * .pi
            let p = c + SIMD2(cos(t), sin(t)) * r
            triangle(c, prev, p, color)
            prev = p
        }
    }

    func ring(_ c: SIMD2<Float>, inner: Float, outer: Float, _ color: SIMD4<Float>, segments: Int = 64) {
        for i in 0..<segments {
            let t0 = Float(i) / Float(segments) * 2 * .pi, t1 = Float(i + 1) / Float(segments) * 2 * .pi
            let u0 = SIMD2(cos(t0), sin(t0)), u1 = SIMD2(cos(t1), sin(t1))
            quad(c + u0 * inner, c + u0 * outer, c + u1 * outer, c + u1 * inner, color)
        }
    }

    // MARK: sprites

    /// Draw a baked image with its registration point at (x, y), rotated (degrees) and scaled.
    func image(_ s: SpriteImage, x: Float, y: Float, rotation: Float = 0, scale: Float = 1,
               tint: SIMD4<Float> = SIMD4(1, 1, 1, 1)) {
        use(s.texture)
        let r = rotation * .pi / 180, cr = cos(r), sr = sin(r)
        func corner(_ lx: Float, _ ly: Float) -> SIMD2<Float> {
            let px = (s.origin.x + lx) * scale, py = (s.origin.y + ly) * scale
            return SIMD2(x + px * cr - py * sr, y + px * sr + py * cr)
        }
        let p0 = corner(0, 0), p1 = corner(s.size.x, 0), p2 = corner(s.size.x, s.size.y), p3 = corner(0, s.size.y)
        push(p0, SIMD2(0, 0), tint); push(p1, SIMD2(1, 0), tint); push(p2, SIMD2(1, 1), tint)
        push(p0, SIMD2(0, 0), tint); push(p2, SIMD2(1, 1), tint); push(p3, SIMD2(0, 1), tint)
    }

    /// Stretch an image over a rectangle (ignores its registration point).
    func image(_ s: SpriteImage, in rect: CGRect, tint: SIMD4<Float> = SIMD4(1, 1, 1, 1)) {
        use(s.texture)
        let x0 = Float(rect.minX), y0 = Float(rect.minY), x1 = Float(rect.maxX), y1 = Float(rect.maxY)
        push(SIMD2(x0, y0), SIMD2(0, 0), tint); push(SIMD2(x1, y0), SIMD2(1, 0), tint); push(SIMD2(x1, y1), SIMD2(1, 1), tint)
        push(SIMD2(x0, y0), SIMD2(0, 0), tint); push(SIMD2(x1, y1), SIMD2(1, 1), tint); push(SIMD2(x0, y1), SIMD2(0, 1), tint)
    }
}

extension SIMD4 where Scalar == Float {
    /// 0xRRGGBB -> linear-ish RGBA used directly by the shader (the original is sRGB-naive too).
    init(rgb: UInt32, alpha: Float = 1) {
        self.init(Float((rgb >> 16) & 255) / 255, Float((rgb >> 8) & 255) / 255, Float(rgb & 255) / 255, alpha)
    }
}
