import AppKit
import CoreText
import MetalKit

/// One baked image: texture plus where its top-left sits relative to the registration point (game units).
struct SpriteImage {
    let texture: MTLTexture
    let file: URL
    let origin: SIMD2<Float>
    let size: SIMD2<Float>
}

/// The asset pack baked from the player's planetracer.swf (assets/), loaded for Metal and SwiftUI.
final class Assets {
    private(set) var sprites: [String: SpriteImage] = [:]
    private var uiImages: [String: NSImage] = [:]
    private var spriteImages: [String: NSImage] = [:]
    private(set) var kingmobileColor = 20
    private(set) var wheelArtRadius: Float = 35
    private(set) var uiFontName = "Helvetica-Bold"
    private(set) var numberFontName = "Helvetica-Bold"
    let root: URL

    private struct Manifest: Decodable {
        struct Entry: Decodable { let file: String; let origin: [Float]; let size: [Float] }
        let scale: Float
        let images: [String: Entry]
        let kingmobileColor: Int?
        let wheelArtRadius: Float?
    }

    init(root: URL, device: MTLDevice) throws {
        self.root = root
        let spriteDir = root.appendingPathComponent("assets/sprites")
        let data = try Data(contentsOf: spriteDir.appendingPathComponent("manifest.json"))
        let m = try JSONDecoder().decode(Manifest.self, from: data)
        kingmobileColor = m.kingmobileColor ?? 20
        wheelArtRadius = m.wheelArtRadius ?? 35
        let loader = MTKTextureLoader(device: device)
        let opts: [MTKTextureLoader.Option: Any] = [
            .SRGB: false, .allocateMipmaps: true, .generateMipmaps: true,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue, .textureStorageMode: MTLStorageMode.private.rawValue,
        ]
        for (name, e) in m.images {
            let url = spriteDir.appendingPathComponent(e.file)
            let tex = try loader.newTexture(URL: url, options: opts)
            sprites[name] = SpriteImage(texture: tex, file: url, origin: SIMD2(e.origin[0], e.origin[1]),
                                        size: SIMD2(Float(tex.width) / m.scale, Float(tex.height) / m.scale))
        }
        registerFonts()
    }

    /// Images from assets/ui (menu backdrop, planet globes, part pictures) for SwiftUI.
    func ui(_ name: String) -> NSImage? {
        if let img = uiImages[name] { return img }
        let url = root.appendingPathComponent("assets/ui/\(name).png")
        guard let img = NSImage(contentsOf: url) else { return nil }
        uiImages[name] = img
        return img
    }

    /// A baked sprite as an NSImage (for the SwiftUI car preview).
    func spriteImage(_ name: String) -> NSImage? {
        if let img = spriteImages[name] { return img }
        guard let s = sprites[name], let img = NSImage(contentsOf: s.file) else { return nil }
        spriteImages[name] = img
        return img
    }

    private func registerFonts() {
        // The game's own lettering: Bitsumishi for menus, Impact for numbers.
        func register(_ file: String) -> String? {
            let url = root.appendingPathComponent("assets/fonts/\(file)")
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  let d = descs.first,
                  let name = CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String else { return nil }
            return name
        }
        if let n = register("ui.ttf") { uiFontName = n }
        if let n = register("numbers.ttf") { numberFontName = n }
    }
}
