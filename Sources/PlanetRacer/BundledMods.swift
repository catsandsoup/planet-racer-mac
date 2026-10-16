import PlanetRacerCore
import SwiftUI

enum BundledMod: String, CaseIterable {
    case moonshot, jellyRacer = "jelly-racer", bigWheels = "big-wheels"

    var name: String {
        switch self {
        case .moonshot: return "MOONSHOT"
        case .jellyRacer: return "JELLY RACER"
        case .bigWheels: return "BIG WHEELS"
        }
    }

    var detail: String {
        switch self {
        case .moonshot: return "LOW GRAVITY. LONG JUMPS."
        case .jellyRacer: return "SOFT SPRINGS. WOBBLY RIDGES."
        case .bigWheels: return "OVERSIZED WHEELS. ROUGH GROUND."
        }
    }
}

extension GameModel {
    /// Keep the base core (including its career) alive while a Quick Race pack is loaded.
    /// Failed loads leave the original core and choices intact.
    func openMod(_ mod: BundledMod, root: URL = Paths.resourceRoot) {
        guard game != nil else { return }
        let data = root.appendingPathComponent("mods/\(mod.rawValue)/data")
        let candidate = pr_create(data.path)
        let error = String(cString: pr_error(candidate))
        guard error.isEmpty else {
            pr_destroy(candidate)
            titleNote = "THIS MOD COULD NOT BE LOADED. \(error)"
            return
        }
        restoreOriginalGame()
        unmoddedGame = game
        unmoddedChoices = choices
        game = candidate
        activeMod = mod
        choices = RaceChoices(planet: 5, opponent: 0, engine: 1, afterburner: 2,
                              chassis: 1, color: 1, tires: 2, difficulty: 0)
        normalizeChoices()
        rebuildOpponents()
        careerRace = false
        titleNote = ""
        go(.quickRace, focus: 8)
    }

    func restoreOriginalGame() {
        guard let original = unmoddedGame else { return }
        if let modified = game { pr_destroy(modified) }
        game = original
        unmoddedGame = nil
        activeMod = nil
        if let originalChoices = unmoddedChoices { choices = originalChoices }
        unmoddedChoices = nil
        rebuildOpponents()
    }
}

struct ModsScreen: View {
    @Bindable var model: GameModel

    var body: some View {
        ZStack {
            Backdrop(image: model.assets?.ui("backdrop"))
            StageCanvas {
                VStack(spacing: 14) {
                    Text("MODS").font(.game(32)).foregroundStyle(Theme.yellow)
                    Text("PICK A QUICK RACE PACK").font(.game(12)).foregroundStyle(.white)
                    ForEach(model.items(.mods)) { item in
                        VStack(spacing: 5) {
                            GameButton(label: item.label, focused: model.focus == item.id, size: 20,
                                       onFocus: { model.focus = item.id },
                                       onTap: { model.activate(.mods, item.id) })
                                .frame(width: 360, height: 36)
                            if let help = item.help {
                                Text(help).font(.game(9)).foregroundStyle(Theme.grey)
                            }
                        }
                    }
                    if !model.titleNote.isEmpty {
                        Text(model.titleNote).font(.game(8)).foregroundStyle(.red)
                            .multilineTextAlignment(.center).lineLimit(3).frame(width: 420)
                    }
                    Text("RETURN TO THE TITLE TO RESTORE THE ORIGINAL GAME.")
                        .font(.game(9)).foregroundStyle(Theme.grey)
                }
            }
            PromptStrip(items: [(model.input.glyph(.confirm), "SELECT"),
                                (model.input.glyph(.back), "BACK")])
        }
    }
}
