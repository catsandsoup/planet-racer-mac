import PlanetRacerCore
import SwiftUI

/// Everything drawn above the Metal view. Also rendered offscreen for the screenshot journey.
struct OverlayView: View {
    @Bindable var model: GameModel
    var body: some View {
        ZStack {
            switch model.screen {
            case .title: TitleScreen(model: model)
            case .quickRace: QuickRaceScreen(model: model)
            case .settings: SettingsScreen(model: model, overlay: false)
            case .race:
                HudOverlay(model: model)
                switch model.phase {
                case .paused: PauseScreen(model: model)
                case .pauseSettings: SettingsScreen(model: model, overlay: true)
                case .results: ResultsScreen(model: model)
                case .playing: EmptyView()
                }
            case .error: ErrorScreen(text: model.errorText)
            case .newCareer: NewCareerScreen(model: model)
            case .loadCareer: LoadCareerScreen(model: model)
            case .garage: GarageScreen(model: model)
            case .shop: ShopScreen(model: model)
            case .planets: PlanetSelectScreen(model: model)
            case .rival: RivalScreen(model: model)
            case .instructions: InstructionsScreen(model: model)
            }
            DialogView(model: model)
        }
    }
}

// MARK: - Title

struct TitleScreen: View {
    @Bindable var model: GameModel
    var body: some View {
        let items = model.items(.title)
        ZStack {
            Backdrop(image: model.assets?.ui("backdrop"))
            StageCanvas {
                VStack(spacing: 0) {
                    Text("PLANET RACER").font(.game(44)).foregroundStyle(Theme.yellow).padding(.top, 18)
                    Text("BY FREEONLINEGAMES.COM").font(.game(12)).foregroundStyle(Theme.yellow)
                    Spacer().frame(height: 30)
                    ForEach(items) { it in
                        let f = model.focus == it.id
                        HStack(spacing: 12) {
                            Arrow(right: true, color: Theme.yellow).opacity(f ? 1 : 0)
                            Text(it.label).font(.game(f ? 22 : 18)).lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(f ? Theme.yellow : Theme.yellowDim)
                            Arrow(right: false, color: Theme.yellow).opacity(f ? 1 : 0)
                        }
                        .frame(height: 34)
                        .contentShape(Rectangle())
                        .onHover { if $0 && Input.mouseActive { model.focus = it.id } }
                        .onTapGesture { model.activate(.title, it.id) }
                    }
                    if !model.titleNote.isEmpty {
                        Text(model.titleNote).font(.game(10)).foregroundStyle(Color(red: 1, green: 0.5, blue: 0.45))
                            .multilineTextAlignment(.center).frame(width: 400).padding(.top, 6)
                    }
                    Spacer()
                }
            }
            PromptStrip(items: [(model.input.glyph(.confirm), "SELECT")])
        }
    }
}

// MARK: - Quick race (garage-style setup)

struct QuickRaceScreen: View {
    @Bindable var model: GameModel
    var body: some View {
        let items = model.items(.quickRace)
        let c = model.choices
        ZStack {
            Backdrop(image: model.assets?.ui("backdrop"))
            StageCanvas {
                ZStack(alignment: .topLeading) {
                    Panel().frame(width: 522, height: 270).offset(x: 14, y: 18)
                    VStack(spacing: 4) {
                        ForEach(items.prefix(8)) { it in
                            SelectorRow(item: it, focused: model.focus == it.id,
                                        onFocus: { model.focus = it.id },
                                        onChange: { d in model.focus = it.id; model.change(.quickRace, it.id, d) })
                        }
                    }
                    .frame(width: 290).offset(x: 24, y: 30)

                    if model.game != nil {
                        let chassis = model.part(Int32(PR_CHASSIS), c.chassis)
                        let tires = model.part(Int32(PR_TIRES), c.tires)
                        CarPreview(assets: model.assets, chassisArt: Int(chassis.art), color: c.color, tireArt: Int(tires.art),
                                   tint: pr_wheel_tint(model.game!, Int32(c.chassis), Int32(c.color)))
                            .frame(width: 200, height: 104).offset(x: 326, y: 30)
                        StatsBlock(model: model).offset(x: 330, y: 150)
                    }

                    HStack(spacing: 12) {
                        GameButton(label: "RACE", focused: model.focus == 8, size: 24,
                                   onFocus: { model.focus = 8 }, onTap: { model.activate(.quickRace, 8) })
                            .frame(width: 140, height: 50)
                        GameButton(label: "BACK", focused: model.focus == 9, size: 16,
                                   onFocus: { model.focus = 9 }, onTap: { model.activate(.quickRace, 9) })
                            .frame(width: 100, height: 50)
                    }
                    .offset(x: 24, y: 300)
                }
                .frame(width: 550, height: 400, alignment: .topLeading)
            }
            PromptStrip(items: [(model.input.glyph(.confirm), "RACE"), (model.input.glyph(.back), "BACK"),
                                (model.input.glyph(.left), "CHANGE")])
        }
    }
}

struct StatsBlock: View {
    @Bindable var model: GameModel
    var body: some View {
        let c = model.choices
        let p = model.planet(c.planet)
        let speed = pr_top_speed(model.game!, Int32(c.engine), Int32(c.chassis))
        let grip = min(1, max(0.05, (0.034 - model.part(Int32(PR_TIRES), c.tires).value) / 0.03))
        VStack(alignment: .leading, spacing: 6) {
            StatBar(label: "SPEED", value: speed)
            StatBar(label: "GRIP", value: grip)
            HStack(alignment: .top, spacing: 10) {
                if let img = model.assets?.ui(String(cString: p.image)) {
                    Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: 62, height: 62)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("GRAVITY \(Int((p.gravity * 100).rounded()))").font(.game(9))
                    Text("BUMPS \(Int(p.surface))%").font(.game(9))
                    Text("LENGTH \(Int(p.size / 1000)) KM").font(.game(9))
                    Text(p.id == 5 ? "RIVAL THE KING" : "RIVAL REP \(Int((Double(model.currentOpponent.rep) / 10).rounded(.up)))/10").font(.game(9))
                }
                .foregroundStyle(.white)
            }
            .padding(.top, 4)
            Text(String(cString: p.description).uppercased()).font(.game(9)).foregroundStyle(Theme.grey)
                .frame(width: 190, alignment: .leading)
        }
    }
}

struct StatBar: View {
    let label: String
    let value: Double
    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.game(11)).foregroundStyle(Theme.yellow).frame(width: 62, alignment: .leading)
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(white: 0.1))
                Rectangle().fill(LinearGradient(colors: [Color(red: 1, green: 1, blue: 0.5), Theme.yellow], startPoint: .top, endPoint: .bottom))
                    .frame(width: 118 * value)
            }
            .frame(width: 118, height: 9)
            .overlay(Rectangle().stroke(Color(white: 0.75), lineWidth: 0.6))
        }
    }
}

/// The configured car, composed from the same baked layers the race uses.
struct CarPreview: View {
    let assets: Assets?
    let chassisArt: Int, color: Int, tireArt: Int
    let tint: UInt32

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let k: CGFloat = 1.0 // game units -> stage units
                let cx = geo.size.width / 2 + 34, cy = geo.size.height / 2 - 8
                ZStack(alignment: .topLeading) {
                    strut(from: (20, 10), to: (40, 32), k: k, cx: cx, cy: cy)
                    strut(from: (-20, 10), to: (-40, 32), k: k, cx: cx, cy: cy)
                    ForEach([(-40.0, 23.0), (40.0, 17.0)], id: \.0) { w in
                        let s = CGFloat(w.1) / CGFloat(assets?.wheelArtRadius ?? 35)
                        layer("wheel/under", x: w.0, y: 32, scale: s, k: k, cx: cx, cy: cy)
                        layer("wheel/color", x: w.0, y: 32, scale: s, k: k, cx: cx, cy: cy, tint: tint)
                        layer("wheel/over", x: w.0, y: 32, scale: s, k: k, cx: cx, cy: cy)
                        layer("wheel/tire_\(tireArt)", x: w.0, y: 32, scale: s, k: k, cx: cx, cy: cy, rotation: t * 240)
                    }
                    layer("car/player/flame_\(Int(t * 36) % 5 + 1)", x: 0, y: 0, scale: 1, k: k, cx: cx, cy: cy)
                    layer("car/player/exhaust_t\(chassisArt)", x: 0, y: 0, scale: 1, k: k, cx: cx, cy: cy)
                    layer("car/player/body_t\(chassisArt)_c\(color)", x: 0, y: 0, scale: 1, k: k, cx: cx, cy: cy)
                }
            }
        }
    }

    private func strut(from a: (CGFloat, CGFloat), to b: (CGFloat, CGFloat), k: CGFloat, cx: CGFloat, cy: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: cx + a.0 * k, y: cy + a.1 * k))
            p.addLine(to: CGPoint(x: cx + b.0 * k, y: cy + b.1 * k))
        }
        .stroke(Color.white, lineWidth: 6 * k)
    }

    @ViewBuilder
    private func layer(_ name: String, x: Double, y: Double, scale: CGFloat, k: CGFloat, cx: CGFloat, cy: CGFloat,
                       tint: UInt32? = nil, rotation: Double = 0) -> some View {
        if let s = assets?.sprites[name], let img = assets?.spriteImage(name) {
            let w = CGFloat(s.size.x) * scale * k, h = CGFloat(s.size.y) * scale * k
            let ox = CGFloat(s.origin.x) * scale * k, oy = CGFloat(s.origin.y) * scale * k
            let anchor = UnitPoint(x: -CGFloat(s.origin.x) / CGFloat(s.size.x), y: -CGFloat(s.origin.y) / CGFloat(s.size.y))
            Group {
                if let tint {
                    Image(nsImage: img).resizable().interpolation(.high).renderingMode(.template).foregroundStyle(Color(rgb: tint))
                } else {
                    Image(nsImage: img).resizable().interpolation(.high)
                }
            }
            .frame(width: w, height: h)
            .rotationEffect(.degrees(rotation), anchor: anchor)
            .offset(x: cx + CGFloat(x) * k + ox, y: cy + CGFloat(y) * k + oy)
        }
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}

// MARK: - Settings (from the title, the macOS menu, or pause)

struct SettingsScreen: View {
    @Bindable var model: GameModel
    let overlay: Bool
    var body: some View {
        let items = model.items(.settings)
        ZStack {
            if overlay { Color(red: 0, green: 0, blue: 0.08).opacity(0.55).ignoresSafeArea() }
            else { Backdrop(image: model.assets?.ui("backdrop")) }
            StageCanvas {
                ZStack(alignment: .top) {
                    Panel().frame(width: 430, height: 290)
                    VStack(spacing: 0) {
                        Text("SETTINGS").font(.game(22)).foregroundStyle(Theme.yellow).padding(.top, 10).padding(.bottom, 12)
                        ForEach(items.prefix(5)) { it in
                            VStack(spacing: 1) {
                                SelectorRow(item: it, focused: model.focus == it.id, labelWidth: 120,
                                            onFocus: { model.focus = it.id },
                                            onChange: { d in model.focus = it.id; model.change(.settings, it.id, d) })
                                Text(model.focus == it.id ? (it.help ?? "") : " ").font(.game(9)).foregroundStyle(Theme.grey)
                                    .frame(height: 12)
                            }
                        }
                        .frame(width: 410)
                        GameButton(label: "BACK", focused: model.focus == 5, size: 16,
                                   onFocus: { model.focus = 5 }, onTap: { model.back(.settings) })
                            .frame(width: 100, height: 34).padding(.top, 6)
                    }
                }
                .frame(width: 550, height: 400, alignment: .center)
                .offset(y: -12)
            }
            PromptStrip(items: [(model.input.glyph(.left), "CHANGE"), (model.input.glyph(.back), "BACK")])
        }
    }
}

// MARK: - Race overlays

/// HUD text, positioned on the same game-unit grid the Metal HUD graphics use.
struct HudOverlay: View {
    @Bindable var model: GameModel
    var body: some View {
        GeometryReader { geo in
            let L = ViewLayout(size: geo.size, framing: model.settings.framing)
            let s = L.scale
            let w = L.widthUnits
            ZStack(alignment: .topLeading) {
                Color.clear
                ZStack(alignment: .topLeading) {
                    Text(model.careerRace ? (model.game.map { String(cString: pr_race_bet_label($0)) } ?? "") : "\(model.hudSeconds) SEC").font(.numbers(11)).foregroundStyle(Theme.yellow)
                        .frame(width: 70).position(x: HudLayout.dial.x, y: HudLayout.dial.y - 7)
                    ExitButton { model.abandon() }
                        .position(x: HudLayout.dial.x, y: HudLayout.dial.y + 9)
                    Text("AFTERBURNER").font(.game(8)).foregroundStyle(Theme.yellow)
                        .frame(width: 120).position(x: w / 2, y: 25)
                    Text("IMPACT").font(.game(9)).foregroundStyle(Theme.grey)
                        .frame(width: 120).position(x: w / 2, y: 47)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("VS \(model.game.map { String(cString: pr_race_opponent_name($0)) }?.uppercased() ?? "")")
                            .font(.game(11)).foregroundStyle(.white)
                        Text(model.careerRace ? "\(model.hudSeconds) SEC" : (model.game.map { String(cString: pr_race_bet_label($0)) } ?? ""))
                            .font(.game(9)).foregroundStyle(Theme.yellow)
                    }
                    .frame(width: 220, alignment: .trailing)
                    .position(x: w - 122, y: 22)
                    if !model.raceStarted && model.phase == .playing {
                        StartPanel(model: model).position(x: w / 2, y: 184)
                    }
                }
                .frame(width: w, height: 400, alignment: .topLeading)
                .scaleEffect(s, anchor: .topLeading)
                .offset(x: L.rect.minX, y: L.rect.minY)
            }
        }
    }
}

struct StartPanel: View {
    @Bindable var model: GameModel
    var body: some View {
        let kb = model.device == .keyboard
        let h = model.input.raceHints
        VStack(spacing: 8) {
            Text(model.game.map { String(cString: pr_race_planet_name($0)) }?.uppercased() ?? "").font(.game(16)).foregroundStyle(Theme.yellow)
            Text(kb ? "PRESS ANY KEY TO RACE" : "PRESS ANY BUTTON TO RACE").font(.game(13)).foregroundStyle(.white)
            VStack(spacing: 5) {
                Text("\(h.accelerate)  ACCELERATE      \(h.reverse)  REVERSE")
                Text("\(h.lean)  LEAN      \(h.boost)  AFTERBURNER")
                Text("\(h.pause)  PAUSE")
            }
            .font(.game(9)).foregroundStyle(Theme.grey).padding(.top, 4)
        }
        .padding(16)
        .frame(width: 300)
        .background(Panel())
    }
}

struct PauseScreen: View {
    @Bindable var model: GameModel
    var body: some View {
        let items = model.items(.pause)
        ZStack {
            Color(red: 0, green: 0, blue: 0.08).opacity(0.45).ignoresSafeArea()
            StageCanvas {
                VStack(spacing: 8) {
                    Text("PAUSED").font(.game(20)).foregroundStyle(Theme.yellow).padding(.bottom, 4)
                    ForEach(items) { it in
                        GameButton(label: it.label, focused: model.focus == it.id,
                                   onFocus: { model.focus = it.id }, onTap: { model.activate(.pause, it.id) })
                            .frame(width: 170, height: 28)
                    }
                    if !model.pauseNote.isEmpty {
                        Text(model.pauseNote).font(.game(8)).foregroundStyle(.white).multilineTextAlignment(.center)
                            .frame(width: 190).padding(.top, 2)
                    }
                }
                .padding(18)
                .background(Panel())
            }
            PromptStrip(items: [(model.input.glyph(.confirm), "SELECT"), (model.input.glyph(.pause), "RESUME")])
        }
    }
}

struct ResultsScreen: View {
    @Bindable var model: GameModel
    var body: some View {
        let items = model.items(.results)
        let won = model.resultHead == "YOU WIN!"
        let head = model.resultHead
        ZStack {
            StageCanvas {
                VStack(spacing: 6) {
                    Text(head).font(.game(26)).foregroundStyle(won ? Theme.yellow : .white)
                    Text(model.resultLine).font(.game(10)).foregroundStyle(.white).multilineTextAlignment(.center)
                    Text("TIME \(Int(model.frame.raceTime)) SEC   DAMAGE \(Int(model.frame.damage))%")
                        .font(.game(9)).foregroundStyle(Theme.grey)
                    Text(model.game.map { String(cString: pr_race_planet_name($0)) }?.uppercased() ?? "")
                        .font(.game(9)).foregroundStyle(Theme.grey).padding(.bottom, 8)
                    ForEach(items) { it in
                        GameButton(label: it.label, focused: model.focus == it.id,
                                   onFocus: { model.focus = it.id }, onTap: { model.activate(.results, it.id) })
                            .frame(width: 170, height: 28)
                    }
                }
                .padding(18)
                .frame(width: 260)
                .background(Panel())
            }
            PromptStrip(items: model.careerRace ? [(model.input.glyph(.confirm), "CONTINUE")]
                        : [(model.input.glyph(.confirm), "SELECT"), (model.input.glyph(.back), "CHANGE CAR")])
        }
    }
}

/// The dial's EXIT (wrecks your car, as in the original), with a finger-sized hit area.
struct ExitButton: View {
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Text("EXIT").font(.game(10)).foregroundStyle(hover ? .white : Theme.yellow)
            .frame(width: 70, height: 30)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.yellow.opacity(hover ? 0.18 : 0)))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture { action() }
    }
}

struct ErrorScreen: View {
    let text: String
    var body: some View {
        ZStack {
            Theme.navy.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Planet Racer can't find its game files").font(.system(size: 22, weight: .bold)).foregroundStyle(.yellow)
                Text(text).font(.system(size: 13)).foregroundStyle(.white).multilineTextAlignment(.center)
                Text("Rebuild the asset pack from your planetracer.swf (see the README), then reopen the app.\nPress any key to quit.")
                    .font(.system(size: 12)).foregroundStyle(.gray).multilineTextAlignment(.center)
            }
            .padding(40)
        }
    }
}
