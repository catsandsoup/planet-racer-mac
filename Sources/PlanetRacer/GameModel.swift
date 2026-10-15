import AppKit
import Observation
import PlanetRacerCore

enum Screen: Hashable {
    case title, quickRace, settings, race, error
    case newCareer, loadCareer, garage, shop, planets, rival, instructions // career
}
enum RacePhase { case playing, paused, pauseSettings, results }
enum MenuContext: Hashable {
    case title, quickRace, settings, pause, results
    case newCareer, loadCareer, garage, shop, planets, rival, instructions, dialog
}

struct MenuItem: Identifiable {
    let id: Int
    let label: String
    var value: String? = nil      // non-nil: a "< value >" selector row
    var help: String? = nil
    var enabled = true
}

/// A modal message box (the original's mcClickOk): text, optional selector/toggle, OK/CANCEL-style buttons.
struct Dialog {
    var title = ""
    var text: String
    var detail = ""
    var buttons = ["OK"]
    var cancel: Int? = 0                  // the button Back/Esc presses (nil: Back does nothing)
    var selector: (label: String, value: () -> String, change: (Int) -> Void)? = nil
    var toggle: (label: String, on: Bool)? = nil
    var onButton: (Int, Dialog) -> Void = { _, _ in }

    var rowCount: Int { (selector == nil ? 0 : 1) + (toggle == nil ? 0 : 1) + buttons.count }
}

/// The whole app's state and rules. SwiftUI views only draw it; every input (keyboard, controller,
/// mouse) goes through the same actions here, so all of them behave identically.
@Observable
final class GameModel {
    // ---- observed by SwiftUI
    var screen = Screen.title
    var phase = RacePhase.playing
    var focus = 0
    var settings = Settings.load()
    var errorText = ""
    var pauseNote = ""
    var device = InputDevice.keyboard
    var hudSeconds = 0
    var raceStarted = false
    var raceResult = Int(PR_RUNNING)
    var resultLine = ""
    var resultHead = ""
    var dialog: Dialog?

    // ---- career (observed)
    var careerRace = false        // the current race is a career race
    var careerSlot: Int?
    var careerRev = 0             // bumped after every career change, so views re-read the core
    var titleNote = ""
    var nameEntry = ""
    var newDifficulty = 1
    var shopTab = 0               // 0 new parts, 1 sell parts
    var shopColor = 1             // paint picked when buying a chassis
    var shopPreviewType = 0
    var loadAction = [Int](repeating: 0, count: Careers.slots) // per slot: 0 load, 1 delete

    // ---- engine state (not observed)
    @ObservationIgnored var game: OpaquePointer?
    @ObservationIgnored var assets: Assets?
    @ObservationIgnored var audio: Audio?
    @ObservationIgnored let input = Input()
    @ObservationIgnored var prevFrame = PRFrame()
    @ObservationIgnored var frame = PRFrame()
    @ObservationIgnored var accumulator = 0.0
    @ObservationIgnored var tickCount = 0
    @ObservationIgnored var frameCount = 0
    @ObservationIgnored var resultTimer = 0.0
    @ObservationIgnored var resultsShownAt = 0.0
    @ObservationIgnored var clock = 0.0
    @ObservationIgnored var oppList: [Int] = []
    @ObservationIgnored var settingsReturn = Screen.title
    @ObservationIgnored var viewSizePoints = CGSize(width: 1280, height: 800)
    @ObservationIgnored var autopilot = false
    @ObservationIgnored var pendingAbandon = false
    @ObservationIgnored var lastFocus: [Screen: Int] = [:]
    @ObservationIgnored var refusalTimer = 0.0
    @ObservationIgnored var textMonitor: Any?
    @ObservationIgnored var scrollMonitor: Any?
    @ObservationIgnored var scrollAccum: CGFloat = 0
    @ObservationIgnored let tick = pr_tick_seconds()

    /// Focus on the screen itself; while a dialog is open this is where the screen's focus will return to.
    var screenFocus: Int { dialog == nil ? focus : (lastFocus[screen] ?? 0) }

    var choices: RaceChoices {
        get { settings.race }
        set { if settings.race != newValue { settings.race = newValue } }
    }

    // MARK: setup

    func load(device mtl: MTLDevice) {
        let root = Paths.resourceRoot
        let g = pr_create(root.appendingPathComponent("data").path)
        if let err = pr_error(g), err.pointee != 0 {
            errorText = String(cString: err)
            screen = .error
            return
        }
        game = g
        do {
            assets = try Assets(root: root, device: mtl)
        } catch {
            errorText = "The asset pack is missing or damaged (\(error.localizedDescription))."
            screen = .error
            return
        }
        audio = Audio(root: root)
        audio?.setVolumes(music: settings.musicVolume, effects: settings.effectsVolume)
        rebuildOpponents()
        installTextEntry()
        installScrolling()
    }

    /// Mouse wheel / trackpad scrolling moves the focus through long lists (shop, saves, planets).
    private func installScrolling() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self, self.dialog == nil, let ctx = self.menuContext,
                  [.shop, .loadCareer, .planets, .garage].contains(ctx) else { return e }
            self.scrollAccum += e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 0.06 : 1)
            let n = self.items(ctx).count
            while abs(self.scrollAccum) >= 1 {
                self.focus = max(0, min(n - 1, self.focus + (self.scrollAccum > 0 ? -1 : 1)))
                self.scrollAccum -= self.scrollAccum > 0 ? 1 : -1
            }
            return nil
        }
    }

    func save() {
        var s = settings
        if ShotScript.enabled { s.lastCareerSlot = Settings.load().lastCareerSlot } // throwaway careers stay out of the player's settings
        s.save()
    }

    // MARK: catalog helpers

    var planetCount: Int { game.map { Int(pr_planet_count($0)) } ?? 0 }
    func planet(_ i: Int) -> PRPlanetInfo { pr_planet(game!, Int32(i)) }
    func part(_ kind: Int32, _ i: Int) -> PRPartInfo { pr_part(game!, kind, Int32(i)) }
    func partCount(_ kind: Int32) -> Int { Int(pr_part_count(game!, kind)) }
    func opponent(_ i: Int) -> PROpponentInfo { pr_opponent(game!, Int32(i)) }
    var currentOpponent: PROpponentInfo { opponent(oppList.isEmpty ? 0 : oppList[min(choices.opponent, oppList.count - 1)]) }

    func rebuildOpponents() {
        guard let g = game else { return }
        oppList = []
        var pid = pr_planet(g, Int32(wrap(choices.planet, planetCount))).id
        if pid == 5 { pid = 1 } // the King races challengers from planet 1's pool
        for i in 0..<Int(pr_opponent_count(g)) where pr_opponent(g, Int32(i)).homePlanet == pid { oppList.append(i) }
        if oppList.isEmpty { oppList = Array(0..<Int(pr_opponent_count(g))) }
        let o = wrap(choices.opponent, oppList.count)
        if o != choices.opponent { choices.opponent = o }
    }

    func wrap(_ v: Int, _ n: Int) -> Int { n <= 0 ? 0 : ((v % n) + n) % n }

    func normalizeChoices() {
        guard game != nil else { return }
        var c = choices
        c.planet = wrap(c.planet, planetCount)
        c.engine = wrap(c.engine, partCount(Int32(PR_ENGINE)))
        c.afterburner = wrap(c.afterburner, partCount(Int32(PR_AFTERBURNER)))
        c.chassis = wrap(c.chassis, partCount(Int32(PR_CHASSIS)))
        c.tires = wrap(c.tires, partCount(Int32(PR_TIRES)))
        let colors = max(1, Int(part(Int32(PR_CHASSIS), c.chassis).colors))
        c.color = wrap(c.color - 1, colors) + 1
        c.difficulty = min(2, max(0, c.difficulty))
        choices = c // writes (and invalidates views) only when something changed
    }

    // MARK: menus (one definition used by keyboard, controller and mouse)

    var menuContext: MenuContext? {
        if dialog != nil { return .dialog }
        switch screen {
        case .title: return .title
        case .quickRace: return .quickRace
        case .settings: return .settings
        case .newCareer: return .newCareer
        case .loadCareer: return .loadCareer
        case .garage: return .garage
        case .shop: return .shop
        case .planets: return .planets
        case .rival: return .rival
        case .instructions: return .instructions
        case .race:
            switch phase {
            case .paused: return .pause
            case .pauseSettings: return .settings
            case .results: return .results
            case .playing: return nil
            }
        case .error: return nil
        }
    }

    func items(_ ctx: MenuContext) -> [MenuItem] {
        switch ctx {
        case .title:
            return titleEntries.enumerated().map { MenuItem(id: $0.offset, label: $0.element.0) }
        case .quickRace:
            guard game != nil else { return [] }
            let c = choices
            let colors = Int(part(Int32(PR_CHASSIS), c.chassis).colors)
            func name(_ k: Int32, _ i: Int) -> String { String(cString: part(k, i).name).uppercased() }
            return [
                MenuItem(id: 0, label: "PLANET", value: String(cString: planet(c.planet).name).uppercased()),
                MenuItem(id: 1, label: "OPPONENT", value: planet(c.planet).id == 5 ? "THE KING" : String(cString: currentOpponent.name).uppercased()),
                MenuItem(id: 2, label: "DIFFICULTY", value: ["EASY", "MEDIUM", "HARD"][c.difficulty]),
                MenuItem(id: 3, label: "ENGINE", value: name(Int32(PR_ENGINE), c.engine)),
                MenuItem(id: 4, label: "AFTERBURNER", value: name(Int32(PR_AFTERBURNER), c.afterburner)),
                MenuItem(id: 5, label: "CHASSIS", value: name(Int32(PR_CHASSIS), c.chassis)),
                MenuItem(id: 6, label: "PAINT", value: "\(c.color) / \(colors)"),
                MenuItem(id: 7, label: "TIRES", value: name(Int32(PR_TIRES), c.tires)),
                MenuItem(id: 8, label: "RACE"),
                MenuItem(id: 9, label: "BACK"),
            ]
        case .settings:
            let s = settings
            return [
                MenuItem(id: 0, label: "WINDOW", value: s.fullscreen ? "FULL SCREEN" : "WINDOWED",
                         help: "Full screen fills your display. Windowed can be resized."),
                MenuItem(id: 1, label: "FRAMING", value: s.framing == .widescreen ? "WIDESCREEN" : "ORIGINAL 4:3",
                         help: "Widescreen shows more of the planet. Original keeps the 2006 view."),
                MenuItem(id: 2, label: "MOTION", value: s.motion == .smooth ? "SMOOTH" : "ORIGINAL 36 FPS",
                         help: "Smooth draws at your display's rate (up to 120 Hz). The physics never change."),
                MenuItem(id: 3, label: "MUSIC", value: "\(s.musicVolume * 10)%", help: "Menu and race music."),
                MenuItem(id: 4, label: "EFFECTS", value: "\(s.effectsVolume * 10)%", help: "Engine, afterburner, crashes."),
                MenuItem(id: 5, label: "BACK"),
            ]
        case .pause:
            let labels = careerRace ? ["RESUME", "SETTINGS", "ABANDON RACE"] : ["RESUME", "RESTART RACE", "SETTINGS", "QUIT TO MENU"]
            return labels.enumerated().map { MenuItem(id: $0.offset, label: $0.element) }
        case .results:
            let labels = careerRace ? ["CONTINUE"] : ["RACE AGAIN", "CHANGE CAR", "MAIN MENU"]
            return labels.enumerated().map { MenuItem(id: $0.offset, label: $0.element) }
        case .dialog:
            return dialogItems()
        default:
            return careerItems(ctx)
        }
    }

    /// Left/right on a selector row (delta -1/+1).
    func change(_ ctx: MenuContext, _ row: Int, _ d: Int) {
        guard d != 0 else { return }
        switch ctx {
        case .quickRace:
            var c = choices
            switch row {
            case 0: c.planet = wrap(c.planet + d, planetCount); choices = c; rebuildOpponents(); c = choices
            case 1: c.opponent = wrap(c.opponent + d, oppList.count)
            case 2: c.difficulty = wrap(c.difficulty + d, 3)
            case 3: c.engine = wrap(c.engine + d, partCount(Int32(PR_ENGINE)))
            case 4: c.afterburner = wrap(c.afterburner + d, partCount(Int32(PR_AFTERBURNER)))
            case 5: c.chassis = wrap(c.chassis + d, partCount(Int32(PR_CHASSIS)))
            case 6: c.color = wrap(c.color - 1 + d, max(1, Int(part(Int32(PR_CHASSIS), c.chassis).colors))) + 1
            case 7: c.tires = wrap(c.tires + d, partCount(Int32(PR_TIRES)))
            default: return
            }
            choices = c
            audio?.play("beep", volume: 0.5)
            save()
        case .settings:
            switch row {
            case 0: settings.fullscreen.toggle(); applyFullscreen()
            case 1: settings.framing = settings.framing == .widescreen ? .original : .widescreen
            case 2: settings.motion = settings.motion == .smooth ? .original : .smooth
            case 3: settings.musicVolume = min(10, max(0, settings.musicVolume + d))
            case 4: settings.effectsVolume = min(10, max(0, settings.effectsVolume + d))
            default: return
            }
            audio?.setVolumes(music: settings.musicVolume, effects: settings.effectsVolume)
            if row == 4 { audio?.play("beep") }
            save()
        case .dialog:
            dialogChange(row, d)
        default:
            careerChange(ctx, row, d)
        }
    }

    func activate(_ ctx: MenuContext, _ row: Int) {
        switch ctx {
        case .title:
            guard row < titleEntries.count else { return }
            titleEntries[row].1()
        case .quickRace:
            if row == 9 { go(.title) } else { startRace() }
        case .settings:
            if row == 5 { back(ctx) } else { change(ctx, row, 1) }
        case .pause:
            if careerRace {
                switch row {
                case 0: resume()
                case 1: phase = .pauseSettings; focus = 0
                default: resume(); abandon()
                }
            } else {
                switch row {
                case 0: resume()
                case 1: startRace()
                case 2: phase = .pauseSettings; focus = 0
                default: quitRace(to: .title)
                }
            }
        case .results:
            guard clock - resultsShownAt > 0.5 else { return } // mashing at the finish never skips the results
            if careerRace { continueAfterCareerRace(); return }
            switch row {
            case 0: startRace()
            case 1: quitRace(to: .quickRace, focus: 8)
            default: quitRace(to: .title)
            }
        case .dialog:
            dialogActivate(row)
        default:
            careerActivate(ctx, row)
        }
    }

    func back(_ ctx: MenuContext) {
        switch ctx {
        case .title: break
        case .quickRace: go(.title)
        case .settings:
            save()
            if screen == .race { phase = .paused; focus = careerRace ? 1 : 2 } else { go(settingsReturn) }
        case .pause: resume()
        case .results:
            guard clock - resultsShownAt > 0.5 else { return }
            if careerRace { continueAfterCareerRace() } else { quitRace(to: .quickRace, focus: 8) }
        case .dialog:
            if let d = dialog, let c = d.cancel { closeDialog(button: c) }
        default:
            careerBack(ctx)
        }
    }

    /// Changes screen, remembering where the focus was on the one we leave.
    func go(_ s: Screen, focus f: Int? = nil) {
        lastFocus[screen] = focus
        screen = s
        focus = f ?? lastFocus[s] ?? 0
        if let n = menuContext.map({ items($0).count }), focus >= n { focus = 0 }
    }

    /// The macOS Settings… menu item opens the same settings screen (paused, if racing).
    func openSettings() {
        if screen == .race {
            if phase == .playing { phase = .paused }
            if phase != .results { phase = .pauseSettings; focus = 0 }
        } else if screen != .error {
            dialog = nil
            settingsReturn = screen == .settings ? settingsReturn : screen
            go(.settings, focus: 0)
        }
    }

    func applyFullscreen() {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        if w.styleMask.contains(.fullScreen) != settings.fullscreen { w.toggleFullScreen(nil) }
    }

    // MARK: dialogs

    func showDialog(_ d: Dialog) {
        lastFocus[screen] = focus
        dialog = d
        focus = (d.selector == nil ? 0 : 1) + (d.toggle == nil ? 0 : 1) // the first button
    }

    private func dialogItems() -> [MenuItem] {
        guard let d = dialog else { return [] }
        var out: [MenuItem] = []
        if let s = d.selector { out.append(MenuItem(id: out.count, label: s.label, value: s.value())) }
        if let t = d.toggle { out.append(MenuItem(id: out.count, label: t.label, value: t.on ? "YES" : "NO")) }
        for b in d.buttons { out.append(MenuItem(id: out.count, label: b)) }
        return out
    }

    private func dialogChange(_ row: Int, _ d: Int) {
        guard var dl = dialog else { return }
        var r = row
        if let s = dl.selector {
            if r == 0 { s.change(d); dialog = dl; audio?.play("beep", volume: 0.5); return }
            r -= 1
        }
        if dl.toggle != nil, r == 0 { dl.toggle!.on.toggle(); dialog = dl }
    }

    private func dialogActivate(_ row: Int) {
        guard let dl = dialog else { return }
        var r = row
        if dl.selector != nil { if r == 0 { dialogChange(row, 1); return }; r -= 1 }
        if dl.toggle != nil { if r == 0 { dialogChange(row, 1); return }; r -= 1 }
        closeDialog(button: r)
    }

    private func closeDialog(button: Int) {
        guard let dl = dialog else { return }
        dialog = nil
        focus = lastFocus[screen] ?? 0
        dl.onButton(button, dl)
    }

    // MARK: race

    func startRace() {
        guard let g = game else { return }
        save()
        let c = choices
        let oppIndex = oppList.isEmpty ? 0 : oppList[min(c.opponent, oppList.count - 1)]
        pr_race_begin(g, PRRaceConfig(planet: Int32(c.planet), opponent: Int32(oppIndex), engine: Int32(c.engine),
                                      tires: Int32(c.tires), chassis: Int32(c.chassis), afterburner: Int32(c.afterburner),
                                      color: Int32(c.color), difficulty: Int32(c.difficulty)))
        careerRace = false
        enterRace()
    }

    /// Shared by Quick Race and career races once the core has set the race up.
    func enterRace() {
        guard let g = game else { return }
        let layout = ViewLayout(size: viewSizePoints, framing: settings.framing)
        pr_race_set_view(g, Double(layout.widthUnits), 400)
        pr_race_frame(g, &frame)
        prevFrame = frame
        accumulator = 0; resultTimer = 0
        audio?.stopRaceLoops()
        audio?.stopMusic()
        audio?.playMusic("race")
        input.latch()
        raceStarted = false; raceResult = Int(PR_RUNNING); hudSeconds = 0
        phase = .playing
        go(.race, focus: 0)
    }

    func resume() { phase = .playing; pauseNote = ""; input.latch() }

    func quitRace(to s: Screen, focus f: Int? = nil) {
        audio?.stopRaceLoops()
        audio?.stopMusic()
        go(s, focus: f)
    }

    func pause(note: String = "") {
        guard screen == .race, phase == .playing else { return }
        phase = .paused; focus = 0; pauseNote = note
    }

    /// The on-dial EXIT, as in the original: wrecks your car.
    func abandon() { pendingAbandon = true }

    // MARK: per-frame

    /// Called by the Metal view once per display refresh.
    func update(dt: Double, viewSize: CGSize, windowFocused: Bool) {
        frameCount += 1
        clock += dt
        viewSizePoints = viewSize
        input.textEntryActive = screen == .newCareer && focus == 0 && dialog == nil
        input.poll(dt: dt)
        if input.device != device { device = input.device }
        if ShotScript.enabled { ShotScript.step(self) }

        if let ctx = menuContext { handleMenuInput(ctx) }

        switch screen {
        case .race: updateRace(dt: dt, windowFocused: windowFocused)
        case .error: if input.anyPressed { NSApp.terminate(nil) }
        case .rival: audio?.playMusic("menuloop"); updateRival(dt: dt)
        default: audio?.playMusic("menuloop")
        }
    }

    private var lastMenuContext: MenuContext?
    private func handleMenuInput(_ ctx: MenuContext) {
        defer { lastMenuContext = ctx }
        guard lastMenuContext == ctx else { return } // the press that opened a menu doesn't act in it
        let list = items(ctx)
        let n = list.count
        if input.pressed(.up) { focus = wrap(focus - 1, n) }
        if input.pressed(.down) { focus = wrap(focus + 1, n) }
        let isSelector = focus < n && list[focus].value != nil
        if isSelector && input.pressed(.left) { change(ctx, focus, -1) }
        if isSelector && input.pressed(.right) { change(ctx, focus, 1) }
        if input.pressed(.confirm) { activate(ctx, focus) }
        else if input.pressed(.back) || (ctx == .pause && input.pressed(.pause)) { back(ctx) }
    }

    private func updateRace(dt: Double, windowFocused: Bool) {
        guard let g = game else { return }
        let layout = ViewLayout(size: viewSizePoints, framing: settings.framing)
        pr_race_set_view(g, Double(layout.widthUnits), 400)

        if phase == .playing {
            if input.pressed(.pause) && lastMenuContext == nil { pause() }
            else if !windowFocused { input.clearKeys(); pause(note: "PAUSED WHILE THE WINDOW WAS IN THE BACKGROUND") }
            else if input.takeLostController() { pause(note: "CONTROLLER DISCONNECTED. RECONNECT, OR USE THE KEYBOARD") }
        }
        if phase == .playing && menuContext == nil { lastMenuContext = nil }

        if pendingAbandon { pendingAbandon = false; pr_race_abandon(g) }

        if phase == .playing || phase == .results {
            if !frame.started && phase == .playing && input.anyPressed && !input.pressed(.pause) {
                pr_race_start(g)
            }
            accumulator += min(dt, 0.25)
            while accumulator >= tick {
                prevFrame = frame
                var inp = phase == .playing ? input.race : PRInput()
                if autopilot && phase == .playing { inp = autopilotInput(g) }
                pr_race_tick(g, inp)
                pr_race_frame(g, &frame)
                accumulator -= tick
                tickCount += 1
            }
            if phase == .playing && frame.result != PR_RUNNING {
                resultTimer += dt
                if resultTimer > 1.6 { showResults() }
            }
        }
        audio?.setPaused(phase == .paused || phase == .pauseSettings)
        if phase == .playing || phase == .results { audio?.update(game: g, frame: frame) }

        if raceStarted != frame.started { raceStarted = frame.started }
        let secs = Int(frame.raceTime)
        if secs != hudSeconds { hudSeconds = secs }
    }

    private func showResults() {
        phase = .results; focus = 0
        resultsShownAt = clock
        input.latch()
        raceResult = Int(frame.result)
        if careerRace, let g = game {
            pr_career_race_settle(g) // money, reputation, wear: settled (and saved) the moment the race ends
            resultHead = String(cString: pr_career_result_head(g)).uppercased()
            resultLine = String(cString: pr_career_result_line(g)).uppercased()
            saveCareer()
            return
        }
        let opp = String(cString: pr_race_opponent_name(game!)).uppercased()
        resultHead = raceResult == Int(PR_WON) ? "YOU WIN!" : raceResult == Int(PR_LOST) ? "YOU LOSE" : "WRECKED!"
        switch raceResult {
        case Int(PR_WON): resultLine = "YOU BEAT \(opp)"
        case Int(PR_LOST): resultLine = "BEATEN BY \(opp)"
        default: resultLine = "YOUR CAR DID NOT SURVIVE"
        }
    }

    /// Interpolation factor between the last two physics ticks (1 = no smoothing, the original look).
    var renderAlpha: Float {
        if settings.motion == .original || phase != .playing && phase != .results { return 1 }
        return Float(accumulator / tick)
    }

    private func autopilotInput(_ g: OpaquePointer) -> PRInput {
        let idx = cArray(frame.bodyIdx, Int32.self, count: Int(frame.bodyCount))
        let pts = cArray(frame.car, PRPoint.self, count: Int(frame.pointCount))
        let bx = idx.reduce(0.0) { $0 + pts[Int($1)].x } / Double(max(1, idx.count))
        let a = pts[Int(frame.bodyA)], b = pts[Int(frame.bodyB)]
        let e = atan2(b.y - a.y, b.x - a.x) * 180 / .pi - pr_ground_slope(g, bx)
        return PRInput(up: true, down: false, left: e > 6, right: e < -6, boost: tickCount % 90 < 20)
    }
}
