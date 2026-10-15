import PlanetRacerCore
import SwiftUI

// Career screens, laid out on the original 550x400 control-centre stage (sprite 732):
// translucent panel with part rows on the left, car and bars on the right, big buttons below.

/// "REPUTATION 2/10   CASH $ 10000" (printCash), plus the certificate badge.
struct CareerStatus: View {
    @Bindable var model: GameModel
    var body: some View {
        let _ = model.careerRev
        let c = model.career
        HStack(spacing: 14) {
            Text("REPUTATION \(Int(c.rep) / 10)/10").foregroundStyle(Theme.yellow)
            Text("CASH $ \(c.cash)").foregroundStyle(.white)
            if c.certificate { Text("CERTIFICATE").foregroundStyle(Theme.grey) }
            if c.youTheKing { Text("THE KING").foregroundStyle(Theme.yellow) }
            Spacer()
            Text(String(cString: c.name).uppercased()).foregroundStyle(Theme.grey)
        }
        .font(.game(11))
        .padding(.horizontal, 10)
        .frame(width: 522, height: 22)
        .background(Theme.band)
    }
}

/// Wear as the original drew it: red damage growing from the left, or green fuel remaining.
struct WearBar: View {
    let wear: Double      // 0..100
    var fuel = false
    var body: some View {
        let v = fuel ? (100 - wear) / 100 : wear / 100
        ZStack(alignment: .leading) {
            Rectangle().fill(fuel ? Color(red: 0.1, green: 0.12, blue: 0.25) : Color(red: 0.2, green: 0.62, blue: 0.2))
            Rectangle().fill(fuel ? Color(red: 0.2, green: 0.5, blue: 1) : Color(red: 0.92, green: 0.15, blue: 0.12))
                .frame(width: 96 * max(0, min(1, v)))
        }
        .frame(width: 96, height: 7)
        .overlay(Rectangle().stroke(Color(white: 0.75), lineWidth: 0.6))
    }
}

/// A focusable list row (planet list, shop items, save slots).
struct ListRow<Trailing: View>: View {
    let label: String
    var tag = ""          // a grey category column before the label
    let focused: Bool
    var enabled = true
    var height: CGFloat = 22
    var onFocus: () -> Void
    var onTap: () -> Void
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 6) {
            if !tag.isEmpty { Text(tag).font(.game(9)).foregroundStyle(Theme.grey).frame(width: 70, alignment: .leading) }
            Text(label).font(.game(12)).foregroundStyle(!enabled ? Theme.grey : focused ? Theme.yellow : .white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 8)
        .frame(height: height)
        .background(LinearGradient(colors: [focused ? Theme.bandFocus : Theme.band.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing))
        .overlay(alignment: .leading) { if focused { Rectangle().fill(Theme.yellow).frame(width: 2.5) } }
        .contentShape(Rectangle())
        .onHover { if $0 && Input.mouseActive { onFocus() } }
        .onTapGesture { onFocus(); onTap() }
    }
}

// MARK: - New career

struct NewCareerScreen: View {
    @Bindable var model: GameModel
    var body: some View {
        let items = model.items(.newCareer)
        ZStack {
            Backdrop(image: model.assets?.ui("backdrop"))
            StageCanvas {
                ZStack(alignment: .top) {
                    Panel().frame(width: 420, height: 250)
                    VStack(spacing: 6) {
                        Text("NEW CAREER").font(.game(22)).foregroundStyle(Theme.yellow).padding(.top, 10)
                        HStack(alignment: .top, spacing: 12) {
                            if let img = model.assets?.ui("driver") {
                                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: 56, height: 70)
                            }
                            VStack(spacing: 4) {
                                ForEach(items.prefix(2)) { it in
                                    SelectorRow(item: nameItem(it), focused: model.screenFocus == it.id, labelWidth: 100,
                                                onFocus: { model.focus = it.id },
                                                onChange: { d in model.focus = it.id; model.change(.newCareer, it.id, d) })
                                }
                                let help = items.indices.contains(model.screenFocus) ? (items[model.screenFocus].help ?? " ") : " "
                                Text(help.uppercased()).font(.game(9)).foregroundStyle(Theme.grey).frame(height: 14)
                            }
                            .frame(width: 310)
                        }
                        .padding(.top, 6)
                        HStack(spacing: 12) {
                            GameButton(label: "START CAREER", focused: model.screenFocus == 2, size: 16,
                                       onFocus: { model.focus = 2 }, onTap: { model.activate(.newCareer, 2) })
                                .frame(width: 180, height: 40)
                            GameButton(label: "BACK", focused: model.screenFocus == 3, size: 14,
                                       onFocus: { model.focus = 3 }, onTap: { model.activate(.newCareer, 3) })
                                .frame(width: 100, height: 40)
                        }
                        .padding(.top, 8)
                        Text("THE KING OF THE MOON AWAITS. BUILD A REPUTATION, WIN MONEY, MOD YOUR CAR.")
                            .font(.game(9)).foregroundStyle(Theme.grey).padding(.top, 6)
                    }
                    .frame(width: 400)
                }
                .frame(width: 550, height: 400).offset(y: 10)
            }
            PromptStrip(items: model.screenFocus == 0
                        ? [("TYPE", "NAME"), (model.input.glyph(.left), "PICK A NAME"), (model.input.glyph(.confirm), "START")]
                        : [(model.input.glyph(.confirm), "SELECT"), (model.input.glyph(.left), "CHANGE"), (model.input.glyph(.back), "BACK")])
        }
    }

    private func nameItem(_ it: MenuItem) -> MenuItem {
        guard it.id == 0, model.screenFocus == 0 else { return it }
        let blink = Int(Date().timeIntervalSinceReferenceDate * 2) % 2 == 0
        return MenuItem(id: 0, label: it.label, value: (it.value ?? "") + (blink ? "_" : " "))
    }
}

// MARK: - Load career

struct LoadCareerScreen: View {
    @Bindable var model: GameModel
    var body: some View {
        let _ = model.careerRev
        let items = model.items(.loadCareer)
        ZStack {
            Backdrop(image: model.assets?.ui("backdrop"))
            StageCanvas {
                ZStack(alignment: .top) {
                    Panel().frame(width: 460, height: 270)
                    VStack(spacing: 5) {
                        Text("LOAD CAREER").font(.game(22)).foregroundStyle(Theme.yellow).padding(.top, 10).padding(.bottom, 6)
                        ForEach(items.prefix(Careers.slots)) { it in
                            let s = Careers.summary(it.id)
                            ListRow(label: "\(it.id + 1)  \(it.label)", focused: model.screenFocus == it.id, enabled: it.enabled, height: 30,
                                    onFocus: { model.focus = it.id }, onTap: { model.activate(.loadCareer, it.id) }) {
                                if let s {
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text("$ \(s.cash)   REP \(s.rep / 10)/10").font(.game(9)).foregroundStyle(.white)
                                        Text((s.youTheKing == true ? "THE KING   " : "") + ["EASY", "MEDIUM", "HARD"][max(0, min(2, s.difficulty))])
                                            .font(.game(9)).foregroundStyle(Theme.grey)
                                    }
                                    HStack(spacing: 4) {
                                        Arrow(right: false, color: model.screenFocus == it.id ? Theme.yellow : Theme.yellowDim)
                                            .onTapGesture { model.focus = it.id; model.change(.loadCareer, it.id, -1) }
                                        Text(it.value ?? "").font(.game(11))
                                            .foregroundStyle(it.value == "DELETE" ? Color(red: 1, green: 0.4, blue: 0.35) : Theme.yellow)
                                            .frame(width: 58)
                                        Arrow(right: true, color: model.screenFocus == it.id ? Theme.yellow : Theme.yellowDim)
                                            .onTapGesture { model.focus = it.id; model.change(.loadCareer, it.id, 1) }
                                    }
                                }
                            }
                        }
                        .frame(width: 430)
                        GameButton(label: "BACK", focused: model.screenFocus == Careers.slots, size: 14,
                                   onFocus: { model.focus = Careers.slots }, onTap: { model.activate(.loadCareer, Careers.slots) })
                            .frame(width: 100, height: 32).padding(.top, 8)
                    }
                }
                .frame(width: 550, height: 400).offset(y: 6)
            }
            PromptStrip(items: [(model.input.glyph(.confirm), "SELECT"), (model.input.glyph(.left), "LOAD / DELETE"),
                                (model.input.glyph(.back), "BACK")])
        }
    }
}

// MARK: - Garage

struct GarageScreen: View {
    @Bindable var model: GameModel
    var body: some View {
        let _ = model.careerRev
        let items = model.items(.garage)
        ZStack {
            Backdrop(image: model.assets?.ui("backdrop"))
            StageCanvas {
                ZStack(alignment: .topLeading) {
                    CareerStatus(model: model).offset(x: 14, y: 8)
                    Panel().frame(width: 522, height: 250).offset(x: 14, y: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(items.prefix(4)) { it in
                            let kind = garageKinds[it.id]
                            VStack(alignment: .leading, spacing: 2) {
                                SelectorRow(item: it, focused: model.screenFocus == it.id, labelWidth: 108,
                                            onFocus: { model.focus = it.id },
                                            onChange: { d in model.focus = it.id; model.change(.garage, it.id, d) })
                                partStatus(kind: kind, focused: model.screenFocus == it.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.focus = it.id; model.activate(.garage, it.id) }
                            }
                        }
                    }
                    .frame(width: 300).offset(x: 24, y: 46)

                    if let g = model.game {
                        let ch = model.ownedPart(Int32(PR_CHASSIS))
                        let tires = model.ownedPart(Int32(PR_TIRES))
                        if let ch {
                            let chArt = Int(model.part(Int32(PR_CHASSIS), Int(ch.type)).art)
                            let tArt = tires.map { Int(model.part(Int32(PR_TIRES), Int($0.type)).art) } ?? 1
                            CarPreview(assets: model.assets, chassisArt: chArt, color: Int(ch.color), tireArt: tArt,
                                       tint: pr_wheel_tint(g, ch.type, ch.color))
                                .frame(width: 190, height: 104).offset(x: 336, y: 52)
                        } else {
                            Text("NO CHASSIS").font(.game(12)).foregroundStyle(Theme.grey).frame(width: 190, height: 104).offset(x: 336, y: 52)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            StatBar(label: "SPEED", value: pr_career_speed_stat(g))
                            StatBar(label: "GRIP", value: pr_career_grip_stat(g))
                            if !pr_career_can_race(g) {
                                Text("REPAIR OR REPLACE PARTS TO RACE").font(.game(9)).foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                            }
                        }
                        .offset(x: 340, y: 186)
                    }

                    HStack(spacing: 10) {
                        ForEach(items.dropFirst(4)) { it in
                            GameButton(label: it.label, focused: model.screenFocus == it.id, size: it.id < 6 ? 22 : 12,
                                       onFocus: { model.focus = it.id }, onTap: { model.activate(.garage, it.id) })
                                .frame(width: it.id < 6 ? 130 : 110, height: 46)
                        }
                    }
                    .offset(x: 14, y: 298)
                }
                .frame(width: 550, height: 400, alignment: .topLeading)
            }
            PromptStrip(items: model.screenFocus < 4
                        ? [(model.input.glyph(.left), "SWAP PART"), (model.input.glyph(.confirm), "REPAIR"), (model.input.glyph(.back), "MAIN MENU")]
                        : [(model.input.glyph(.confirm), "SELECT"), (model.input.glyph(.back), "MAIN MENU")])
        }
    }

    @ViewBuilder
    private func partStatus(kind: Int32, focused: Bool) -> some View {
        if let p = model.ownedPart(kind), let g = model.game {
            let fuel = kind == Int32(PR_AFTERBURNER)
            let price = Int(pr_career_repair_price(g, kind))
            HStack(spacing: 8) {
                Text(fuel ? "FUEL" : kind == Int32(PR_TIRES) ? "WEAR" : "DAMAGE").font(.game(9)).foregroundStyle(Theme.grey)
                    .frame(width: 56, alignment: .leading)
                WearBar(wear: p.wear, fuel: fuel)
                Text(p.wear > 0 ? "\(fuel ? "REFUEL" : "REPAIR") $ \(price)" : (fuel ? "FULL" : "AS NEW"))
                    .font(.game(9)).foregroundStyle(p.wear > 0 && focused ? Theme.yellow : Theme.grey)
            }
            .padding(.leading, 12)
            .frame(height: 13)
        } else {
            Text("NONE: BUY ONE IN THE SHOP").font(.game(9)).foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                .padding(.leading, 12).frame(height: 13)
        }
    }
}

// MARK: - Shop

struct ShopScreen: View {
    @Bindable var model: GameModel
    var body: some View {
        let _ = model.careerRev
        let rows = model.shopRows()
        let n = rows.count
        let visible = 7
        let sel = max(0, min(n - 1, model.screenFocus - 1))
        let start = max(0, min(n - visible, sel - visible / 2))
        ZStack {
            Backdrop(image: model.assets?.ui("backdrop"))
            StageCanvas {
                ZStack(alignment: .topLeading) {
                    CareerStatus(model: model).offset(x: 14, y: 8)
                    Panel().frame(width: 522, height: 250).offset(x: 14, y: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CAR PARTS TRADE CENTER").font(.game(17)).foregroundStyle(.white)
                        SelectorRow(item: MenuItem(id: 0, label: "PARTS", value: model.shopTab == 0 ? "NEW PARTS" : "SELL PARTS"),
                                    focused: model.screenFocus == 0, labelWidth: 70,
                                    onFocus: { model.focus = 0 }, onChange: { d in model.focus = 0; model.change(.shop, 0, d) })
                        HStack {
                            Text("PART").padding(.leading, 76)
                            Spacer()
                            Text(model.shopTab == 0 ? "STOCK" : "WEAR").frame(width: 50, alignment: .trailing)
                            Text(model.shopTab == 0 ? "PRICE" : "VALUE").frame(width: 70, alignment: .trailing)
                        }
                        .font(.game(9)).foregroundStyle(Theme.grey).padding(.horizontal, 8).padding(.top, 2).frame(width: 300)
                        if n == 0 {
                            Text("YOU HAVE NOTHING TO SELL").font(.game(10)).foregroundStyle(Theme.grey).padding(8)
                        }
                        ForEach(start..<min(n, start + visible), id: \.self) { i in
                            let r = rows[i]
                            ListRow(label: r.name, tag: model.kindNoun(r.kind).uppercased(), focused: model.screenFocus == i + 1,
                                    enabled: r.enabled, height: 20,
                                    onFocus: { model.focus = i + 1 }, onTap: { model.activate(.shop, i + 1) }) {
                                if r.inUse { Text("FITTED").font(.game(8)).foregroundStyle(Theme.yellow) }
                                Text(r.detail).font(.game(11)).foregroundStyle(.white).frame(width: 40, alignment: .trailing)
                                Text("$ \(r.price)").font(.game(11)).foregroundStyle(Theme.yellow).frame(width: 70, alignment: .trailing)
                            }
                        }
                        if n > visible {
                            Text("\(start + 1)-\(min(n, start + visible)) OF \(n)").font(.game(9)).foregroundStyle(Theme.grey).padding(.leading, 8)
                        }
                    }
                    .frame(width: 300, alignment: .leading).offset(x: 24, y: 42)

                    ShopPicture(model: model, row: (1...n).contains(model.screenFocus) ? rows[model.screenFocus - 1] : nil)
                        .frame(width: 190, height: 230).offset(x: 336, y: 46)

                    HStack(spacing: 10) {
                        GameButton(label: "GARAGE", focused: model.screenFocus == n + 1, size: 20,
                                   onFocus: { model.focus = n + 1 }, onTap: { model.activate(.shop, n + 1) })
                            .frame(width: 130, height: 46)
                        GameButton(label: "RACE", focused: model.screenFocus == n + 2, size: 20,
                                   onFocus: { model.focus = n + 2 }, onTap: { model.activate(.shop, n + 2) })
                            .frame(width: 130, height: 46)
                    }
                    .offset(x: 14, y: 298)
                }
                .frame(width: 550, height: 400, alignment: .topLeading)
            }
            PromptStrip(items: [(model.input.glyph(.confirm), model.shopTab == 0 ? "BUY" : "SELL"),
                                (model.input.glyph(.left), "NEW / SELL"), (model.input.glyph(.back), "GARAGE")])
        }
    }
}

/// The shop's picture panel: the focused item, as the original's "picture" clip showed it.
struct ShopPicture: View {
    @Bindable var model: GameModel
    let row: ShopRow?
    var body: some View {
        VStack(spacing: 6) {
            if let r = row, model.game != nil {
                partPicture(kind: r.kind, type: r.type, color: model.shopTab == 1 ? ownedColor(r) : 1)
                    .frame(width: 180, height: 110)
                Text(r.name).font(.game(15)).foregroundStyle(Theme.yellow)
                Text(describe(r)).font(.game(9)).foregroundStyle(.white).multilineTextAlignment(.center)
                if model.shopTab == 0 && !r.enabled { Text("SOLD OUT").font(.game(11)).foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4)) }
            } else {
                Spacer()
                Text("BITS\n&\nPIECES").font(.game(24)).foregroundStyle(.white).multilineTextAlignment(.center)
                Spacer()
            }
        }
    }

    private func ownedColor(_ r: ShopRow) -> Int {
        guard r.kind == Int32(PR_CHASSIS), let g = model.game else { return 1 }
        return Int(pr_career_part(g, r.kind, Int32(r.index)).color)
    }

    private func describe(_ r: ShopRow) -> String {
        let p = model.part(r.kind, r.type)
        switch r.kind {
        case Int32(PR_ENGINE): return "ENGINE POWER x\(String(format: "%.1f", p.value))"
        case Int32(PR_CHASSIS): return "CHASSIS SPEED x\(String(format: "%.1f", p.value))\n\(p.colors) PAINT JOBS"
        case Int32(PR_TIRES): return "GRIP \(Int(((0.05 - p.value) / 0.05 * 100).rounded()))%"
        default: return "ABOUT \(Int(p.value)) SECONDS OF BOOST"
        }
    }

    @ViewBuilder
    func partPicture(kind: Int32, type: Int, color: Int) -> some View {
        let art = Int(model.part(kind, type).art)
        switch kind {
        case Int32(PR_ENGINE), Int32(PR_AFTERBURNER):
            let name = kind == Int32(PR_ENGINE) ? "engine_\(min(3, type + 1))" : "afterburner_\(min(3, type + 1))"
            if let img = model.assets?.ui(name) {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            }
        case Int32(PR_CHASSIS):
            CarPreview(assets: model.assets, chassisArt: art, color: color, tireArt: 1,
                       tint: pr_wheel_tint(model.game!, Int32(type), Int32(color)))
        default:
            if let img = model.assets?.spriteImage("wheel/tire_\(art)") {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: 90, height: 90)
                    .background(Circle().fill(Color(white: 0.35)).frame(width: 60, height: 60))
            }
        }
    }
}

// MARK: - Planet select

struct PlanetSelectScreen: View {
    @Bindable var model: GameModel
    var body: some View {
        let _ = model.careerRev
        let items = model.items(.planets)
        let id = min(5, model.screenFocus + 1)
        ZStack {
            Backdrop(image: model.assets?.ui("backdrop"))
            StageCanvas {
                ZStack(alignment: .topLeading) {
                    CareerStatus(model: model).offset(x: 14, y: 8)
                    Panel().frame(width: 522, height: 280).offset(x: 14, y: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SELECT A PLANET").font(.game(17)).foregroundStyle(Theme.yellow).padding(.bottom, 4)
                        ForEach(items.prefix(5)) { it in
                            let pid = it.id + 1
                            ListRow(label: it.label, focused: model.screenFocus == it.id, height: 34,
                                    onFocus: { model.focus = it.id }, onTap: { model.activate(.planets, it.id) }) {
                                if (pid == 1 || pid == 2) && !model.career.certificate {
                                    Text("CERTIFICATE").font(.game(8)).foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                                }
                                Text(it.value ?? "").font(.game(11)).foregroundStyle(Theme.yellow)
                            }
                            .overlay(alignment: .leading) {
                                if let p = model.planetInfo(id: pid), let img = model.assets?.ui(String(cString: p.image)) {
                                    Image(nsImage: img).resizable().interpolation(.high).frame(width: 26, height: 26).offset(x: -32)
                                }
                            }
                        }
                        GameButton(label: "BACK", focused: model.screenFocus == 5, size: 14,
                                   onFocus: { model.focus = 5 }, onTap: { model.activate(.planets, 5) })
                            .frame(width: 100, height: 30).padding(.top, 6)
                    }
                    .frame(width: 250).offset(x: 62, y: 44)

                    if model.screenFocus < 5, let p = model.planetInfo(id: id), let g = model.game {
                        VStack(spacing: 5) {
                            if let img = model.assets?.ui(String(cString: p.image)) {
                                Image(nsImage: img).resizable().interpolation(.high).frame(width: 96, height: 96)
                            }
                            Text(String(cString: p.name).uppercased()).font(.game(15)).foregroundStyle(Theme.yellow)
                            VStack(alignment: .leading, spacing: 3) {
                                info("SIZE", describe("size", p.size))
                                info("SURFACE", describe("surface", p.surface))
                                info("GRAVITY", describe("gravity", p.gravity))
                                info("TRAVEL", "$ \(pr_career_travel_cost(g, Int32(id)))")
                                info("RIVALS", id == 5 ? "THE KING" : "\(pr_career_opponents_on(g, Int32(id)))")
                            }
                            Text(String(cString: p.description).uppercased()).font(.game(9)).foregroundStyle(Theme.grey)
                                .multilineTextAlignment(.center).frame(width: 190)
                        }
                        .frame(width: 200).offset(x: 328, y: 44)
                    }
                }
                .frame(width: 550, height: 400, alignment: .topLeading)
            }
            PromptStrip(items: [(model.input.glyph(.confirm), "TRAVEL"), (model.input.glyph(.back), "GARAGE")])
        }
    }

    private func info(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(Theme.grey).frame(width: 70, alignment: .leading); Text(v.uppercased()).foregroundStyle(.white) }
            .font(.game(10))
    }

    /// planetDescriptions() from the original.
    private func describe(_ type: String, _ v: Double) -> String {
        switch type {
        case "surface": return v < 30 ? "flat" : v < 60 ? "bumpy" : v < 80 ? "hills" : "mountainous"
        case "size": return v < 9000 ? "tiny" : v < 13000 ? "small" : v < 16000 ? "medium" : "huge"
        default: return v < 0.2 ? "very low" : v < 0.22 ? "low" : v < 0.26 ? "medium" : "very high"
        }
    }
}

// MARK: - Rival encounter (the opponent-select scene)

struct RivalScreen: View {
    @Bindable var model: GameModel
    var body: some View {
        let _ = model.careerRev
        let e = model.encounter
        let c = model.career
        let acts = model.rivalActions()
        let items = model.items(.rival)
        ZStack {
            StationBackdrop(model: model, planet: Int(c.planet), kingGame: e.kingGame)
            StageCanvas {
                ZStack(alignment: .topLeading) {
                    CareerStatus(model: model).offset(x: 14, y: 8)
                    HStack(spacing: 10) {
                        Text(model.planetName(Int(c.planet))).foregroundStyle(Theme.yellow)
                        Spacer()
                        if !e.kingGame { Text("TIME \(c.planetTime)/\(c.timeLimit)").foregroundStyle(Theme.grey) }
                    }
                    .font(.game(11)).frame(width: 510).offset(x: 20, y: 36)

                    if e.state != Int32(PR_ENC_NONE), model.game != nil {
                        opponentCard(e).frame(width: 236, height: 222).offset(x: 14, y: 56)
                        panel(e, acts: acts, items: items).frame(width: 276, height: 222).offset(x: 260, y: 56)
                    }

                    if let home = items.last {
                        GameButton(label: home.label, focused: model.screenFocus == home.id, size: 12,
                                   onFocus: { model.focus = home.id }, onTap: { model.activate(.rival, home.id) })
                            .frame(width: 120, height: 32).offset(x: 416, y: 290)
                    }
                }
                .frame(width: 550, height: 400, alignment: .topLeading)
            }
            PromptStrip(items: prompts(acts))
        }
    }

    private func prompts(_ acts: [(RivalAction, String)]) -> [(String, String)] {
        var p = [(model.input.glyph(.confirm), "SELECT")]
        if acts.contains(where: { $0.0 == .stake }) { p.append((model.input.glyph(.left), "BET")) }
        return p
    }

    private func opponentCard(_ e: PREncounter) -> some View {
        let o = model.opponent(Int(e.opponent))
        let ch = Int(model.part(Int32(PR_CHASSIS), max(0, Int(o.chassis) - 1)).art)
        let tires = Int(model.part(Int32(PR_TIRES), max(0, Int(o.wheels) - 1)).art)
        return ZStack(alignment: .top) {
            Panel(fill: Theme.rivalPanel)
            VStack(spacing: 4) {
                // initPanelValues(): portrait, name and reputation; the King wears the crown
                HStack(alignment: .center, spacing: 16) {
                    RivalPortrait(assets: model.assets, face: Int(o.face), frame: Int(o.faceFrame), crown: e.oppKing)
                        .frame(width: 66, height: 92)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(e.oppKing ? "THE KING" : String(cString: o.name).uppercased()).font(.game(15)).foregroundStyle(Theme.yellow)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(e.oppKing ? "REPUTATION: KING" : "REPUTATION: \(Int((Double(o.rep) / 10).rounded(.up)))/10")
                            .font(.game(10)).foregroundStyle(Theme.yellow)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.top, 10)
                CarPreview(assets: model.assets, chassisArt: e.oppKing ? 3 : ch,
                           color: e.oppKing ? (model.assets?.kingmobileColor ?? 20) : Int(e.oppColor),
                           tireArt: e.oppKing ? 3 : tires,
                           tint: e.oppKing ? 0xFFFF00 : pr_wheel_tint(model.game!, Int32(max(0, Int(o.chassis) - 1)), e.oppColor))
                    .frame(width: 200, height: 96)
                if e.oppKing { Text("DRIVES THE KINGMOBILE").font(.game(9)).foregroundStyle(.white) }
                if e.youKing { Text("A CHALLENGER FOR YOUR CROWN").font(.game(9)).foregroundStyle(.white) }
            }
        }
    }

    @ViewBuilder
    private func panel(_ e: PREncounter, acts: [(RivalAction, String)], items: [MenuItem]) -> some View {
        ZStack(alignment: .top) {
            Panel(fill: Theme.rivalPanel)
            VStack(spacing: 6) {
                switch Int(e.state) {
                case Int(PR_ENC_VEHICLE_UPDATE):
                    Text("VEHICLE UPDATE").font(.game(16)).foregroundStyle(Theme.yellow).padding(.top, 10)
                    vehicleRow("ENGINE", Int32(PR_ENGINE))
                    vehicleRow("CHASSIS", Int32(PR_CHASSIS))
                    vehicleRow("AFTERBURNER", Int32(PR_AFTERBURNER))
                    vehicleRow("TIRES", Int32(PR_TIRES))
                case Int(PR_ENC_WAIT_KING):
                    Text("YOU ARE THE KING").font(.game(16)).foregroundStyle(Theme.yellow).padding(.top, 10)
                    Text("CHALLENGERS PAY $ 100000 TO RACE YOU, WIN OR LOSE.").font(.game(10)).foregroundStyle(.white)
                        .multilineTextAlignment(.center).frame(width: 240)
                default:
                    Text("\"\(String(cString: e.sentence))\"").font(.game(11)).foregroundStyle(.white)
                        .multilineTextAlignment(.center).lineLimit(5).minimumScaleFactor(0.8)
                        .frame(width: 250, height: 70).padding(.top, 8)
                    if e.state == Int32(PR_ENC_OFFER) && (e.initialAmount == 2 || e.initialAmount == 4) {
                        Text("RACE FOR \(model.stakeText(e.amount))").font(.game(15)).foregroundStyle(Theme.yellow)
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: 5) {
                    ForEach(Array(acts.dropLast().enumerated()), id: \.offset) { i, a in
                        if a.0 == .stake {
                            SelectorRow(item: items[i], focused: model.screenFocus == i, labelWidth: 84,
                                        onFocus: { model.focus = i }, onChange: { d in model.focus = i; model.change(.rival, i, d) })
                        } else {
                            GameButton(label: a.1, focused: model.screenFocus == i, size: a.0 == .car ? 12 : 15,
                                       color: a.0 == .accept || a.0 == .race ? Theme.accept : a.0 == .decline ? Theme.decline : nil,
                                       onFocus: { model.focus = i }, onTap: { model.activate(.rival, i) })
                                .frame(height: 26)
                        }
                    }
                }
                .frame(width: 250).padding(.bottom, 10)
            }
        }
    }

    private func vehicleRow(_ label: String, _ kind: Int32) -> some View {
        HStack {
            Text(label).font(.game(10)).foregroundStyle(.white).frame(width: 110, alignment: .leading)
            if let p = model.ownedPart(kind) { WearBar(wear: p.wear, fuel: kind == Int32(PR_AFTERBURNER)) }
        }
    }
}

// MARK: - Instructions

struct InstructionsScreen: View {
    @Bindable var model: GameModel
    var body: some View {
        ZStack {
            Backdrop(image: model.assets?.ui("backdrop"))
            StageCanvas {
                ZStack(alignment: .top) {
                    Panel().frame(width: 500, height: 300)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("HOW THE CAREER WORKS").font(.game(18)).foregroundStyle(Theme.yellow)
                        Group {
                            Text("GOAL: beat the King of the Moon and take the crown. The trip to the Moon costs $ 100000.")
                            Text("RIVALS: travel to a planet and rivals pull up one by one. Accept their bet, change it and negotiate, offer to race for the cars (pink slips), or decline. Turn people down too often and they lose their temper.")
                            Text("REPUTATION: wins against better drivers raise it fastest. At 3/10 you get the certificate for planets 1 and 2.")
                            Text("WEAR: landings and crashes wear the engine, chassis and tires; boosting uses fuel. Repair and refuel in the garage. Worn parts make the car slower and slide more.")
                            Text("TIME: after about 20 rivals and races it's time to go home. Each trip home restocks the shop.")
                        }
                        .font(.game(10)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Spacer()
                            GameButton(label: "OK", focused: true, size: 16, onFocus: {}, onTap: { model.activate(.instructions, 0) })
                                .frame(width: 100, height: 32)
                        }
                    }
                    .frame(width: 470).padding(.top, 14)
                }
                .frame(width: 550, height: 400).offset(y: -6)
            }
            PromptStrip(items: [(model.input.glyph(.confirm), "OK")])
        }
    }
}

// MARK: - Dialog (mcClickOk)

struct DialogView: View {
    @Bindable var model: GameModel
    var body: some View {
        if let d = model.dialog {
            let items = model.items(.dialog)
            let firstButton = items.count - d.buttons.count
            ZStack {
                Color(red: 0, green: 0, blue: 0.08).opacity(0.5).ignoresSafeArea()
                StageCanvas {
                    VStack(spacing: 8) {
                        if !d.title.isEmpty { Text(d.title.uppercased()).font(.game(16)).foregroundStyle(Theme.yellow) }
                        Text(d.text).font(.game(12)).foregroundStyle(.white).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if !d.detail.isEmpty {
                            Text(d.detail).font(.game(10)).foregroundStyle(Theme.grey).multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if d.selector != nil, let g = model.game {
                            CarPreview(assets: model.assets, chassisArt: Int(model.part(Int32(PR_CHASSIS), model.shopPreviewType).art),
                                       color: model.shopColor, tireArt: 1,
                                       tint: pr_wheel_tint(g, Int32(model.shopPreviewType), Int32(model.shopColor)))
                                .frame(width: 200, height: 96)
                        }
                        ForEach(items.prefix(firstButton)) { it in
                            SelectorRow(item: it, focused: model.focus == it.id, labelWidth: 120,
                                        onFocus: { model.focus = it.id },
                                        onChange: { dd in model.focus = it.id; model.change(.dialog, it.id, dd) })
                        }
                        HStack(spacing: 12) {
                            ForEach(items.dropFirst(firstButton)) { it in
                                GameButton(label: it.label, focused: model.focus == it.id, size: 14,
                                           onFocus: { model.focus = it.id }, onTap: { model.activate(.dialog, it.id) })
                                    .frame(width: 100, height: 30)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(18)
                    .frame(width: 320)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color(white: 0.13).opacity(0.97))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.panelBorder, lineWidth: Theme.border)))
                }
                PromptStrip(items: [(model.input.glyph(.confirm), "SELECT"), (model.input.glyph(.back), "CANCEL")])
            }
        }
    }
}


/// The opponent-select scene's backdrop (startOppSelect): sky, the planet's station domes, the ground.
struct StationBackdrop: View {
    @Bindable var model: GameModel
    let planet: Int
    let kingGame: Bool
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.height / 400, geo.size.width / 550)
            let ox = (geo.size.width - 550 * s) / 2, oy = (geo.size.height - 400 * s) / 2
            let name = kingGame ? "scene/buildings_king" : "scene/buildings_buildings\(planet)"
            let fill = model.planetInfo(id: planet).map { Color(rgb: $0.fill) } ?? Color(white: 0.8)
            ZStack(alignment: .topLeading) {
                if let sky = model.assets?.spriteImage("scene/sky") {
                    Image(nsImage: sky).resizable().frame(width: geo.size.width, height: geo.size.height)
                } else { Theme.navy }
                if let a = model.assets, let sp = a.sprites[name], let img = a.spriteImage(name) {
                    Image(nsImage: img).resizable().interpolation(.high)
                        .frame(width: CGFloat(sp.size.x) * s, height: CGFloat(sp.size.y) * s)
                        .offset(x: ox + CGFloat(sp.origin.x) * s, y: oy + CGFloat(sp.origin.y) * s)
                }
                Rectangle().fill(fill)
                    .frame(width: geo.size.width, height: max(0, geo.size.height - (oy + 330 * s)))
                    .offset(y: oy + 330 * s)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

/// A rival's portrait from the original opponent panel (face type 1-5, expression frame), with the
/// King's crown on top. Images are baked in the face clip's own units (assets/sprites/faces).
struct RivalPortrait: View {
    let assets: Assets?
    let face: Int
    let frame: Int
    var crown = false
    var body: some View {
        GeometryReader { geo in
            let k = min(geo.size.width / 62, geo.size.height / 96) // the face clip is about 62 x 96 units
            ZStack(alignment: .topLeading) {
                layer("faces/face\(face)_\(frame)", k: k) ?? layer("faces/face\(face)_1", k: k)
                if crown { layer("faces/crown", k: k) }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    private func layer(_ name: String, k: CGFloat) -> AnyView? {
        guard let s = assets?.sprites[name], let img = assets?.spriteImage(name) else { return nil }
        return AnyView(Image(nsImage: img).resizable().interpolation(.high)
            .frame(width: CGFloat(s.size.x) * k, height: CGFloat(s.size.y) * k)
            .offset(x: (CGFloat(s.origin.x) + 2) * k, y: (CGFloat(s.origin.y) + 3) * k))
    }
}
