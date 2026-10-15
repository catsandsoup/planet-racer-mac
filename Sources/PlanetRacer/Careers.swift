import Foundation

/// The five career save slots: career-1.json … career-5.json in ~/Library/Application Support/Planet Racer/.
/// The core writes and reads the JSON (pr_career_to_json / pr_career_load_json); this only stores files.
enum Careers {
    static let slots = 5

    /// What the load screen shows for a slot, read straight from the save.
    struct Summary: Decodable {
        let name: String
        let cash: Int
        let rep: Int
        let difficulty: Int
        let youTheKing: Bool?
    }

    static var dir: URL {
        // the screenshot journey plays with throwaway careers, never the player's own
        if let shots = ShotScript.dir {
            let d = URL(fileURLWithPath: shots).appendingPathComponent("careers", isDirectory: true)
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            return d
        }
        return Paths.userDir
    }

    static func url(_ slot: Int) -> URL { dir.appendingPathComponent("career-\(slot + 1).json") }

    static func exists(_ slot: Int) -> Bool { FileManager.default.fileExists(atPath: url(slot).path) }

    static func summary(_ slot: Int) -> Summary? {
        guard let data = try? Data(contentsOf: url(slot)) else { return nil }
        return try? JSONDecoder().decode(Summary.self, from: data)
    }

    static func read(_ slot: Int) -> String? {
        guard let data = try? Data(contentsOf: url(slot)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Atomic: a crash or power cut mid-write leaves the previous save intact.
    @discardableResult
    static func write(_ slot: Int, _ json: String) -> Bool {
        (try? Data(json.utf8).write(to: url(slot), options: .atomic)) != nil
    }

    static func delete(_ slot: Int) { try? FileManager.default.removeItem(at: url(slot)) }

    static var firstFree: Int? { (0..<slots).first { !exists($0) } }
}
