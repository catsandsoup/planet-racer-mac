import Foundation

enum Framing: String, Codable { case widescreen, original }   // original = the 550x400 4:3 view
enum Motion: String, Codable { case smooth, original }        // smooth = interpolated to the display rate

/// The last Quick Race choices, so a returning player is one press from racing.
struct RaceChoices: Codable, Equatable {
    var planet = 2, opponent = 0, engine = 0, afterburner = 0, chassis = 0, color = 1, tires = 0, difficulty = 1
}

/// Player settings, stored as JSON in ~/Library/Application Support/Planet Racer/settings.json.
struct Settings: Codable, Equatable {
    var fullscreen = false
    var framing = Framing.widescreen
    var motion = Motion.smooth
    var musicVolume = 8      // 0...10
    var effectsVolume = 8    // 0...10
    var race = RaceChoices()
    var lastCareerSlot: Int? = nil   // CONTINUE on the title screen

    init() {}

    // Tolerant decoding: a missing or unknown key keeps its default instead of resetting everything.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fullscreen = (try? c.decode(Bool.self, forKey: .fullscreen)) ?? fullscreen
        framing = (try? c.decode(Framing.self, forKey: .framing)) ?? framing
        motion = (try? c.decode(Motion.self, forKey: .motion)) ?? motion
        musicVolume = min(10, max(0, (try? c.decode(Int.self, forKey: .musicVolume)) ?? musicVolume))
        effectsVolume = min(10, max(0, (try? c.decode(Int.self, forKey: .effectsVolume)) ?? effectsVolume))
        race = (try? c.decode(RaceChoices.self, forKey: .race)) ?? race
        lastCareerSlot = try? c.decode(Int.self, forKey: .lastCareerSlot)
    }

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: Paths.settingsFile),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return s
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(self) else { return }
        try? data.write(to: Paths.settingsFile, options: .atomic)
    }
}

enum Paths {
    /// Folder holding assets/ and data/: the app bundle's Resources, or the source tree when run with `swift run`.
    static let resourceRoot: URL = {
        let fm = FileManager.default
        func ok(_ u: URL) -> Bool {
            fm.fileExists(atPath: u.appendingPathComponent("data/parts.json").path) &&
                fm.fileExists(atPath: u.appendingPathComponent("assets/sprites/manifest.json").path)
        }
        if let env = ProcessInfo.processInfo.environment["PLANETRACER_ROOT"] { return URL(fileURLWithPath: env) }
        if let res = Bundle.main.resourceURL, ok(res) { return res }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            if ok(dir) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: fm.currentDirectoryPath)
    }()

    static let userDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Planet Racer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var settingsFile: URL { userDir.appendingPathComponent("settings.json") }
}
