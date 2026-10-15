import AppKit
import PlanetRacerCore

/// Garage rows in the original's order, and the core part kind each one edits.
let garageKinds: [Int32] = [Int32(PR_ENGINE), Int32(PR_AFTERBURNER), Int32(PR_CHASSIS), Int32(PR_TIRES)]
let garageLabels = ["ENGINE", "AFTERBURNER", "CHASSIS", "TIRES"]
/// Shop sections in the original's order (Engines, Chassis, Tires, Afterburners).
let shopKinds: [Int32] = [Int32(PR_ENGINE), Int32(PR_CHASSIS), Int32(PR_TIRES), Int32(PR_AFTERBURNER)]

struct ShopRow {
    let kind: Int32
    let index: Int        // catalogue type (new) or owned-part index (sell)
    let type: Int
    let name: String
    let detail: String    // stock, or wear %
    let price: Int
    let enabled: Bool
    let inUse: Bool
}

enum RivalAction { case stake, car, accept, decline, ok, race, wait, goHome }

let presetNames = ["ZOOT", "ROCKET", "MOONDUST", "TURBO", "COMET", "NOVA", "ZIGGY", "ORBIT"]

/// Career mode: everything here forwards to the core (pr_career_*) and then saves.
extension GameModel {

    // MARK: title

    var titleEntries: [(String, () -> Void)] {
        var out: [(String, () -> Void)] = []
        if let slot = settings.lastCareerSlot, let s = Careers.summary(slot) {
            out.append(("CONTINUE  \(s.name.uppercased())", { [unowned self] in loadCareer(slot) }))
        }
        out.append(("NEW CAREER", { [unowned self] in newCareer() }))
        out.append(("LOAD CAREER", { [unowned self] in titleNote = ""; go(.loadCareer, focus: 0) }))
        out.append(("QUICK RACE", { [unowned self] in titleNote = ""; rebuildOpponents(); go(.quickRace) }))
        out.append(("SETTINGS", { [unowned self] in titleNote = ""; settingsReturn = .title; go(.settings) }))
        out.append(("QUIT", { NSApp.terminate(nil) }))
        return out
    }

    func newCareer() {
        guard Careers.firstFree != nil else {
            titleNote = "ALL \(Careers.slots) CAREER SLOTS ARE FULL. DELETE ONE IN LOAD CAREER FIRST."
            audio?.play("beep")
            return
        }
        titleNote = ""
        nameEntry = ""
        newDifficulty = 1
        go(.newCareer, focus: 0)
    }

    // MARK: core access

    var career: PRCareerInfo { pr_career_info(game!) }
    var encounter: PREncounter { pr_career_encounter(game!) }

    /// After any career change: redraw and save (atomically) to the current slot.
    func careerChanged() {
        careerRev &+= 1
        saveCareer()
    }

    func saveCareer() {
        guard let g = game, let slot = careerSlot else { return }
        Careers.write(slot, String(cString: pr_career_to_json(g)))
    }

    func loadCareer(_ slot: Int) {
        guard let g = game else { return }
        guard let json = Careers.read(slot), pr_career_load_json(g, json) else {
            showDialog(Dialog(text: "This saved career could not be read.",
                              detail: game.map { String(cString: pr_career_error($0)) } ?? ""))
            return
        }
        careerSlot = slot
        titleNote = ""
        settings.lastCareerSlot = slot
        save()
        if pr_career_start_garage(g) { // the King lives on the Moon
            audio?.play("warp")
            careerChanged()
            go(.rival, focus: 0)
        } else {
            careerChanged()
            enterGarage()
        }
    }

    func enterGarage() {
        audio?.play("garage")
        go(.garage)
        careerRev &+= 1
        showGarageMessages()
    }

    /// clickOkAfterRace and the certificate award, shown once on arriving home.
    private func showGarageMessages() {
        guard let g = game else { return }
        let trouble = pr_career_take_trouble(g)
        let cert = pr_career_take_certificate(g)
        let certDialog = Dialog(title: "CERTIFICATE",
                                text: "Congratulations! You have been awarded a certificate to race on all planets!")
        var text = ""
        switch trouble {
        case Int32(PR_TROUBLE_CAR_LOST): text = "You have lost your car."
        case Int32(PR_TROUBLE_TIME): text = "It's time to go home."
        case Int32(PR_TROUBLE_DAMAGE): text = "Your car has been badly damaged. You will need to do repairs before you can race again."
        default: break
        }
        if !text.isEmpty {
            showDialog(Dialog(text: text, onButton: { [unowned self] _, _ in if cert { showDialog(certDialog) } }))
        } else if cert {
            showDialog(certDialog)
        }
        saveCareer()
    }

    // MARK: part helpers

    func ownedPart(_ kind: Int32) -> PROwnedPart? {
        guard let g = game, pr_career_part_count(g, kind) > 0 else { return nil }
        return pr_career_part(g, kind, pr_career_current(g, kind))
    }

    func partName(_ kind: Int32, _ type: Int) -> String { String(cString: part(kind, type).name).uppercased() }

    func shopRows() -> [ShopRow] {
        guard let g = game else { return [] }
        var rows: [ShopRow] = []
        for k in shopKinds {
            if shopTab == 0 {
                for t in 0..<partCount(k) {
                    let stock = Int(pr_career_stock(g, k, Int32(t)))
                    rows.append(ShopRow(kind: k, index: t, type: t, name: partName(k, t), detail: "\(stock)",
                                        price: Int(part(k, t).price), enabled: stock > 0, inUse: false))
                }
            } else {
                let cur = Int(pr_career_current(g, k))
                for i in 0..<Int(pr_career_part_count(g, k)) {
                    let p = pr_career_part(g, k, Int32(i))
                    rows.append(ShopRow(kind: k, index: i, type: Int(p.type), name: partName(k, Int(p.type)),
                                        detail: "\(Int(p.wear.rounded()))%", price: Int(pr_career_sell_value(g, k, Int32(i))),
                                        enabled: true, inUse: i == cur))
                }
            }
        }
        return rows
    }

    func rivalActions() -> [(RivalAction, String)] {
        let e = encounter
        var out: [(RivalAction, String)] = []
        switch Int(e.state) {
        case Int(PR_ENC_WAIT_KING): out = [(.wait, "WAIT FOR A CHALLENGER")]
        case Int(PR_ENC_VEHICLE_UPDATE): out = [(.ok, "OK")]
        case Int(PR_ENC_OFFER):
            if e.initialAmount == 4 { out = [(.accept, "ACCEPT")] }
            else if e.initialAmount == 2 { out = [(.accept, "ACCEPT"), (.decline, "DECLINE")] }
            else {
                out = [(.stake, "RACE FOR"), (.car, "RACE FOR THE CAR"),
                       (.accept, e.negotiating ? "NEGOTIATE" : "ACCEPT"), (.decline, "DECLINE")]
            }
        case Int(PR_ENC_ACCEPTED): out = [(.race, "RACE")]
        case Int(PR_ENC_DECLINED), Int(PR_ENC_NO_CASH), Int(PR_ENC_REFUSED): out = [(.ok, "OK")]
        default: break
        }
        out.append((.goHome, e.kingGame ? "MAIN MENU" : "GO HOME"))
        return out
    }

    func stakeText(_ amount: Int32) -> String {
        switch amount {
        case 2: return "THE CAR"
        case 4: return "THE CROWN"
        default: return "$ \(amount)"
        }
    }

    // MARK: menus

    func careerItems(_ ctx: MenuContext) -> [MenuItem] {
        _ = careerRev
        switch ctx {
        case .newCareer:
            return [
                MenuItem(id: 0, label: "NAME", value: nameEntry.isEmpty ? (focus == 0 ? "" : "TYPE A NAME") : nameEntry.uppercased(),
                         help: "Type your name, or press left / right for one."),
                MenuItem(id: 1, label: "DIFFICULTY", value: ["EASY", "MEDIUM", "HARD"][newDifficulty],
                         help: ["Start with $ 14000. Rivals are slower.", "Start with $ 10000.", "Start with $ 6000. Rivals are faster."][newDifficulty]),
                MenuItem(id: 2, label: "START CAREER"),
                MenuItem(id: 3, label: "BACK"),
            ]
        case .loadCareer:
            var out: [MenuItem] = []
            for slot in 0..<Careers.slots {
                if let s = Careers.summary(slot) {
                    out.append(MenuItem(id: slot, label: s.name.uppercased(), value: loadAction[slot] == 0 ? "LOAD" : "DELETE"))
                } else {
                    out.append(MenuItem(id: slot, label: "EMPTY", enabled: false))
                }
            }
            out.append(MenuItem(id: Careers.slots, label: "BACK"))
            return out
        case .garage:
            guard let g = game else { return [] }
            var out: [MenuItem] = []
            for (i, k) in garageKinds.enumerated() {
                let n = Int(pr_career_part_count(g, k))
                var value = "NONE"
                if let p = ownedPart(k) {
                    value = partName(k, Int(p.type))
                    if n > 1 { value += "  \(Int(pr_career_current(g, k)) + 1)/\(n)" }
                }
                out.append(MenuItem(id: i, label: garageLabels[i], value: value))
            }
            for (i, l) in ["RACE", "SHOP", "INSTRUCTIONS", "MAIN MENU"].enumerated() { out.append(MenuItem(id: 4 + i, label: l)) }
            return out
        case .shop:
            var out = [MenuItem(id: 0, label: "PARTS", value: shopTab == 0 ? "NEW PARTS" : "SELL PARTS")]
            for (i, r) in shopRows().enumerated() { out.append(MenuItem(id: 1 + i, label: r.name, enabled: r.enabled)) }
            out.append(MenuItem(id: out.count, label: "GARAGE"))
            out.append(MenuItem(id: out.count, label: "RACE"))
            return out
        case .planets:
            guard let g = game else { return [] }
            var out: [MenuItem] = []
            for id in 1...5 {
                let cost = Int(pr_career_travel_cost(g, Int32(id)))
                out.append(MenuItem(id: id - 1, label: planetName(id), value: "$ \(cost)"))
            }
            out.append(MenuItem(id: 5, label: "BACK"))
            return out
        case .rival:
            return rivalActions().enumerated().map { MenuItem(id: $0.offset, label: $0.element.1,
                                                              value: $0.element.0 == .stake ? stakeText(encounter.amount) : nil) }
        case .instructions:
            return [MenuItem(id: 0, label: "OK")]
        default:
            return []
        }
    }

    func planetName(_ id: Int) -> String {
        guard let g = game else { return "" }
        for i in 0..<planetCount where pr_planet(g, Int32(i)).id == id { return String(cString: pr_planet(g, Int32(i)).name).uppercased() }
        return "PLANET \(id)"
    }

    func planetInfo(id: Int) -> PRPlanetInfo? {
        guard let g = game else { return nil }
        for i in 0..<planetCount where pr_planet(g, Int32(i)).id == id { return pr_planet(g, Int32(i)) }
        return nil
    }

    func careerChange(_ ctx: MenuContext, _ row: Int, _ d: Int) {
        guard let g = game else { return }
        switch ctx {
        case .newCareer:
            if row == 0 {
                let i = presetNames.firstIndex(of: nameEntry.uppercased()) ?? (d > 0 ? -1 : 0)
                nameEntry = presetNames[wrap(i + d, presetNames.count)]
            } else if row == 1 { newDifficulty = wrap(newDifficulty + d, 3) }
            audio?.play("beep", volume: 0.5)
        case .loadCareer:
            if row < Careers.slots && Careers.exists(row) { loadAction[row] = 1 - loadAction[row]; audio?.play("beep", volume: 0.5) }
        case .garage:
            guard row < 4 else { return }
            let k = garageKinds[row]
            let before = pr_career_current(g, k)
            pr_career_select(g, k, Int32(d))
            if pr_career_current(g, k) != before { audio?.play("beep", volume: 0.5); careerChanged() }
        case .shop:
            if row == 0 { shopTab = 1 - shopTab; audio?.play("beep", volume: 0.5) }
        case .rival:
            let acts = rivalActions()
            if row < acts.count, acts[row].0 == .stake {
                pr_career_adjust_amount(g, Int32(d))
                audio?.play("beep", volume: 0.5)
                careerRev &+= 1
            }
        default: break
        }
    }

    func careerActivate(_ ctx: MenuContext, _ row: Int) {
        guard let g = game else { return }
        switch ctx {
        case .newCareer:
            switch row {
            case 0, 1: focus = row + 1
            case 2: startNewCareer()
            default: back(.newCareer)
            }
        case .loadCareer:
            if row >= Careers.slots { back(.loadCareer); return }
            guard let s = Careers.summary(row) else { return }
            if loadAction[row] == 0 { loadCareer(row); return }
            showDialog(Dialog(title: "DELETE CAREER", text: "Delete \(s.name)'s career? This can't be undone.",
                              buttons: ["DELETE", "CANCEL"], cancel: 1, onButton: { [unowned self] b, _ in
                guard b == 0 else { return }
                Careers.delete(row)
                loadAction[row] = 0
                if settings.lastCareerSlot == row { settings.lastCareerSlot = nil; save() }
                careerRev &+= 1
            }))
        case .garage:
            switch row {
            case 0...3: repairDialog(garageKinds[row])
            case 4:
                if pr_career_can_race(g) { go(.planets, focus: 2) }
                else { showDialog(Dialog(text: "Your car is not complete, or badly damaged.")) }
            case 5: shopTab = 0; go(.shop, focus: 1)
            case 6: go(.instructions, focus: 0)
            default: back(.garage)
            }
        case .shop:
            let rows = shopRows()
            if row == 0 { careerChange(.shop, 0, 1); return }
            if row == rows.count + 1 { audio?.play("garage"); go(.garage) ; return }
            if row == rows.count + 2 { careerActivate(.garage, 4); return }
            shopDialog(rows[row - 1])
        case .planets:
            if row >= 5 { back(.planets) } else { travel(to: row + 1) }
        case .rival:
            rivalActivate(row)
        case .instructions:
            back(.instructions)
        default: break
        }
    }

    func careerBack(_ ctx: MenuContext) {
        switch ctx {
        case .newCareer, .loadCareer: go(.title)
        case .garage: go(.title, focus: 0)
        case .shop, .planets, .instructions: audio?.play("garage"); go(.garage)
        case .rival: focus = rivalActions().count - 1 // to GO HOME, never straight out
        default: break
        }
    }

    // MARK: flows

    func startNewCareer() {
        guard let g = game else { return }
        let name = nameEntry.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { focus = 0; audio?.play("beep"); return }
        guard let slot = Careers.firstFree else { newCareer(); return }
        pr_career_new(g, name, Int32(newDifficulty))
        careerSlot = slot
        settings.lastCareerSlot = slot
        save()
        careerChanged()
        lastFocus[.garage] = 4
        enterGarage()
    }

    private func repairDialog(_ kind: Int32) {
        guard let g = game, let p = ownedPart(kind) else { audio?.play("beep"); return }
        guard p.wear > 0 else { audio?.play("beep", volume: 0.5); return }
        let price = Int(pr_career_repair_price(g, kind))
        let fuel = kind == Int32(PR_AFTERBURNER)
        let text = (fuel ? "Refuelling" : "Repairing") + " this item will cost $ \(price)"
        if career.cash < price {
            showDialog(Dialog(title: fuel ? "REFUEL" : "REPAIR", text: text, detail: "You do not have enough money to do the repair."))
            return
        }
        showDialog(Dialog(title: fuel ? "REFUEL" : "REPAIR", text: text, buttons: ["OK", "CANCEL"], cancel: 1,
                          onButton: { [unowned self] b, _ in
            guard b == 0 else { return }
            pr_career_repair(g, kind)
            audio?.play("beep")
            careerChanged()
        }))
    }

    private func shopDialog(_ r: ShopRow) {
        guard let g = game else { return }
        if shopTab == 0 {
            guard r.enabled else { audio?.play("beep", volume: 0.5); return }
            var d = Dialog(title: "BUY", text: "Buy the \(r.name.lowercased()) \(kindNoun(r.kind)) for $ \(r.price)?",
                           buttons: ["BUY", "CANCEL"], cancel: 1)
            if r.kind == Int32(PR_CHASSIS) {
                shopColor = 1
                shopPreviewType = r.type
                let colors = max(1, Int(part(r.kind, r.type).colors))
                d.selector = (label: "PAINT", value: { [unowned self] in "\(shopColor) / \(colors)" },
                              change: { [unowned self] dd in shopColor = wrap(shopColor - 1 + dd, colors) + 1 })
            }
            d.onButton = { [unowned self] b, _ in
                guard b == 0 else { return }
                let res = pr_career_buy(g, r.kind, Int32(r.type), Int32(shopColor))
                if res == Int32(PR_NOT_ENOUGH_CASH) { showDialog(Dialog(text: "You do not have enough money to buy this item.")); return }
                audio?.play("beep")
                careerChanged()
            }
            showDialog(d)
        } else {
            let note = r.inUse ? "It is fitted to your car right now." : ""
            showDialog(Dialog(title: "SELL", text: "Sell your \(r.name.lowercased()) \(kindNoun(r.kind)) (\(r.detail) worn) for $ \(r.price)?",
                              detail: note, buttons: ["SELL", "CANCEL"], cancel: 1, onButton: { [unowned self] b, _ in
                guard b == 0 else { return }
                pr_career_sell(g, r.kind, Int32(r.index))
                audio?.play("beep")
                careerChanged()
                let n = items(.shop).count
                if focus >= n { focus = max(0, n - 3) }
            }))
        }
    }

    func kindNoun(_ k: Int32) -> String {
        switch k {
        case Int32(PR_ENGINE): return "engine"
        case Int32(PR_TIRES): return "tires"
        case Int32(PR_CHASSIS): return "chassis"
        default: return "afterburner"
        }
    }

    private func travel(to id: Int) {
        guard let g = game else { return }
        let c = career
        let cost = Int(pr_career_travel_cost(g, Int32(id)))
        if (id == 1 || id == 2) && !c.certificate {
            showDialog(Dialog(title: "TRAVEL", text: "You need a certificate to race on this planet.",
                              detail: "To get a certificate your reputation must be at least 3/10."))
            return
        }
        if Int(c.cash) < cost {
            showDialog(Dialog(title: "TRAVEL", text: "Travelling to this planet will cost $ \(cost)",
                              detail: "You do not have enough money to travel."))
            return
        }
        let go: () -> Void = { [unowned self] in
            guard pr_career_travel(g, Int32(id)) == Int32(PR_OK) else { return }
            audio?.play("warp")
            careerChanged()
            refusalTimer = 0
            if career.planet == 0 { enterGarage() } else { self.go(.rival, focus: defaultRivalFocus()) }
        }
        if c.noTravelMessage { go(); return }
        let desc = planetInfo(id: id).map { String(cString: $0.description) } ?? ""
        showDialog(Dialog(title: planetName(id), text: "Travelling to this planet will cost $ \(cost)", detail: desc,
                          buttons: ["OK", "CANCEL"], cancel: 1, toggle: (label: "DON'T ASK AGAIN", on: false),
                          onButton: { [unowned self] b, d in
            guard b == 0 else { return }
            if d.toggle?.on == true { pr_career_set_no_travel_message(g, true) }
            go()
        }))
    }

    func defaultRivalFocus() -> Int {
        rivalActions().firstIndex { $0.0 == .accept || $0.0 == .race || $0.0 == .ok || $0.0 == .wait } ?? 0
    }

    private func rivalActivate(_ row: Int) {
        guard let g = game else { return }
        let acts = rivalActions()
        guard row < acts.count else { return }
        switch acts[row].0 {
        case .stake: careerChange(.rival, row, 1); return
        case .car: pr_career_offer_car(g)
        case .accept, .race:
            if pr_career_accept(g) { startCareerRace(); return }
        case .decline: pr_career_decline(g)
        case .ok, .wait: pr_career_continue(g)
        case .goHome:
            let toTitle = pr_career_go_home(g)
            careerChanged()
            if toTitle { go(.title, focus: 0) } else { enterGarage() }
            return
        }
        audio?.play("beep", volume: 0.5)
        afterRivalChange()
    }

    private func afterRivalChange() {
        careerChanged()
        refusalTimer = 0
        if career.planet == 0 { enterGarage(); return }
        focus = min(defaultRivalFocus(), items(.rival).count - 1)
    }

    /// Per frame on the rival screen: the "chicken" panel closes itself after 2 s (opponentWaitInt).
    func updateRival(dt: Double) {
        guard let g = game, dialog == nil else { return }
        if career.planet == 0 { enterGarage(); return }
        if encounter.state == Int32(PR_ENC_REFUSED) {
            refusalTimer += dt
            if refusalTimer > 2 {
                pr_career_refusal_elapsed(g)
                afterRivalChange()
            }
        }
    }

    func startCareerRace() {
        guard let g = game else { return }
        pr_career_race_begin(g)
        careerRace = true
        careerChanged()
        enterRace()
    }

    func continueAfterCareerRace() {
        audio?.stopRaceLoops()
        audio?.stopMusic()
        careerRace = false
        careerRev &+= 1
        if career.planet != 0 { refusalTimer = 0; go(.rival, focus: defaultRivalFocus()) } else { enterGarage() }
    }

    // MARK: name entry (keyboard typing goes here while the NAME row has focus)

    func installTextEntry() {
        textMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.screen == .newCareer, self.focus == 0, self.dialog == nil,
                  !e.modifierFlags.contains(.command) else { return e }
            switch e.keyCode {
            case 51, 117: if !self.nameEntry.isEmpty { self.nameEntry.removeLast() }
            case 36, 76: self.focus = 2; self.activate(.newCareer, 2)
            case 53: self.back(.newCareer)
            case 125, 48: self.focus = 1
            case 126: self.focus = 3
            case 123, 124: self.change(.newCareer, 0, e.keyCode == 124 ? 1 : -1)
            default:
                let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -'.!_"))
                for ch in e.characters ?? "" where self.nameEntry.count < 14 {
                    if ch.unicodeScalars.allSatisfy({ allowed.contains($0) }) { self.nameEntry.append(ch) }
                }
            }
            return nil
        }
    }
}
