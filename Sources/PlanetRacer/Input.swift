import AppKit
import GameController
import PlanetRacerCore

enum MenuAction: Int, CaseIterable { case up, down, left, right, confirm, back, pause }
enum InputDevice { case keyboard, xbox, playStation }

/// Keyboard (app-level key monitor) + game controllers (GameController framework), polled once a frame.
final class Input {
    private var keysDown = Set<UInt16>()
    private var keysPressed = Set<UInt16>()      // went down since the last poll (menu edges)
    private var tappedSinceSample = Set<UInt16>() // went down since the last race sample (keeps sub-tick taps)
    private var anyKeyPressed = false
    private var monitor: Any?
    private var edges = Set<MenuAction>()
    private var heldPrev = [Bool](repeating: false, count: 4)
    private var repeatTimer = [Double](repeating: 0, count: 4)
    private var padHeldPrev = Set<String>()
    private var padPressed = Set<String>()
    private var latchedKeys = Set<UInt16>()       // still held from before a menu closed
    private var latchedPad = Set<String>()
    private var shiftHeld = false
    private var lastMouseLocation = NSPoint.zero
    private(set) var device = InputDevice.keyboard
    private var lostController = false
    /// True once after the controller being used was unplugged.
    func takeLostController() -> Bool { defer { lostController = false }; return lostController }

    /// Hover may only move menu focus while the mouse is really moving, so a resting cursor never
    /// steals focus from the keyboard/controller when a new screen appears under it.
    static private(set) var lastMouseMove: CFTimeInterval = 0
    static var mouseActive: Bool { CACurrentMediaTime() - lastMouseMove < 0.3 }

    /// While a text field has focus (e.g. a name entry), keys go to it instead of the game.
    var textEntryActive = false

    // macOS virtual key codes
    enum Key {
        static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
        static let space: UInt16 = 49, ret: UInt16 = 36, enter: UInt16 = 76, esc: UInt16 = 53, delete: UInt16 = 51
        static let tab: UInt16 = 48
        static let w: UInt16 = 13, a: UInt16 = 0, s: UInt16 = 1, d: UInt16 = 2, p: UInt16 = 35
        static let fnArrows: Set<UInt16> = [115, 116, 119, 121] // Home/PgUp/End/PgDn = fn + arrows on laptops
    }

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] e in
            guard let self else { return e }
            if e.type == .flagsChanged {
                self.shiftHeld = e.modifierFlags.contains(.shift)
                // fn released before its arrow: the arrow's keyUp may arrive under another code
                if !e.modifierFlags.contains(.function) { self.keysDown.subtract(Key.fnArrows) }
                return e
            }
            // Releases are always recorded, even with ⌘ held, so no key can get stuck down.
            if e.type == .keyUp {
                self.keysDown.remove(e.keyCode)
                return (e.modifierFlags.contains(.command) || self.textEntryActive) ? e : nil
            }
            if e.modifierFlags.contains(.command) || self.textEntryActive { return e } // ⌘Q, ⌘, text fields
            if !e.isARepeat {
                self.keysPressed.insert(e.keyCode)
                self.tappedSinceSample.insert(e.keyCode)
                self.anyKeyPressed = true
            }
            self.keysDown.insert(e.keyCode)
            self.device = .keyboard
            NSCursor.setHiddenUntilMouseMoves(true)
            return nil // swallow: no system beep, and Esc never drops the window out of full screen
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.device != .keyboard && GCController.controllers().isEmpty { self.lostController = true; self.device = .keyboard }
        }
        // Key-ups never arrive while another app is in front, so forget everything held.
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.clearKeys()
        }
    }

    /// Releases every held key (e.g. when the window loses focus, keyUp events never arrive).
    func clearKeys() {
        keysDown.removeAll()
        tappedSinceSample.removeAll()
        latchedKeys.removeAll()
    }

    private var pad: GCExtendedGamepad? { GCController.current?.extendedGamepad ?? GCController.controllers().first?.extendedGamepad }

    private struct PadState {
        var buttons = Set<String>()   // digital buttons plus "rt"/"lt"/"stick-*" when past their thresholds
        var lx: Float = 0, ly: Float = 0, rt: Float = 0, lt: Float = 0
    }

    private func padState() -> PadState {
        guard let g = pad else { return PadState() }
        var s = PadState(lx: g.leftThumbstick.xAxis.value, ly: g.leftThumbstick.yAxis.value,
                         rt: g.rightTrigger.value, lt: g.leftTrigger.value)
        let map: [(GCControllerButtonInput, String)] = [
            (g.dpad.up, "up"), (g.dpad.down, "down"), (g.dpad.left, "left"), (g.dpad.right, "right"),
            (g.buttonA, "a"), (g.buttonB, "b"), (g.buttonX, "x"), (g.buttonY, "y"),
            (g.rightShoulder, "rb"), (g.leftShoulder, "lb"), (g.buttonMenu, "menu"),
        ]
        for (b, name) in map where b.isPressed { s.buttons.insert(name) }
        // analog inputs count as "pressed" past a threshold, so pulling RT can start a race
        if s.rt > 0.2 { s.buttons.insert("rt") }
        if s.lt > 0.2 { s.buttons.insert("lt") }
        if s.lx < -0.5 { s.buttons.insert("stick-left") }
        if s.lx > 0.5 { s.buttons.insert("stick-right") }
        if s.ly > 0.5 { s.buttons.insert("stick-up") }
        if s.ly < -0.5 { s.buttons.insert("stick-down") }
        return s
    }

    /// Call once per frame.
    func poll(dt: Double) {
        let loc = NSEvent.mouseLocation
        if loc != lastMouseLocation { lastMouseLocation = loc; Input.lastMouseMove = CACurrentMediaTime() }

        let ps = padState()
        padPressed = ps.buttons.subtracting(padHeldPrev)
        padHeldPrev = ps.buttons
        if !padPressed.isEmpty {
            let name = (GCController.current ?? GCController.controllers().first)?.productCategory ?? ""
            device = name.contains("DualSense") || name.contains("DualShock") || name.contains("PS") ? .playStation : .xbox
            NSCursor.setHiddenUntilMouseMoves(true)
        }
        // a latched key/button is released for good once it is let go
        latchedKeys.formIntersection(keysDown)
        latchedPad.formIntersection(ps.buttons)

        func k(_ c: UInt16) -> Bool { keysDown.contains(c) }
        func kp(_ c: UInt16) -> Bool { keysPressed.contains(c) }
        let b = ps.buttons
        let held = [
            k(Key.up) || k(Key.w) || b.contains("up") || b.contains("stick-up"),
            k(Key.down) || k(Key.s) || b.contains("down") || b.contains("stick-down"),
            k(Key.left) || k(Key.a) || b.contains("left") || b.contains("stick-left"),
            k(Key.right) || k(Key.d) || b.contains("right") || b.contains("stick-right"),
        ]
        edges.removeAll()
        let dirs: [MenuAction] = [.up, .down, .left, .right]
        for i in 0..<4 {
            if held[i] && !heldPrev[i] { edges.insert(dirs[i]); repeatTimer[i] = 0.35 }
            else if held[i] {
                repeatTimer[i] -= dt
                if repeatTimer[i] <= 0 { edges.insert(dirs[i]); repeatTimer[i] = 0.09 }
            }
            heldPrev[i] = held[i]
        }
        if kp(Key.tab) { edges.insert(shiftHeld ? .up : .down) }
        if kp(Key.ret) || kp(Key.enter) || kp(Key.space) || padPressed.contains("a") { edges.insert(.confirm) }
        if kp(Key.esc) || kp(Key.delete) || padPressed.contains("b") { edges.insert(.back) }
        if kp(Key.esc) || kp(Key.p) || padPressed.contains("menu") { edges.insert(.pause) }
        anyEdge = anyKeyPressed || !padPressed.isEmpty
        keysPressed.removeAll()
        anyKeyPressed = false
    }

    private var anyEdge = false
    func pressed(_ a: MenuAction) -> Bool { edges.contains(a) }
    /// "Press any key/button" (keyboard, controller buttons, triggers or stick).
    var anyPressed: Bool { anyEdge }

    /// Called when a menu closes into the race: whatever is held right now is ignored until it is
    /// released, so the press that closed the menu never leaks into the race. Everything else works.
    func latch() {
        latchedKeys = keysDown
        latchedPad = padState().buttons
    }

    /// Held race controls, sampled once per physics tick. A key tapped and released between two
    /// ticks still counts for one tick.
    var race: PRInput {
        let ps = padState()
        let keys = keysDown.union(tappedSinceSample).subtracting(latchedKeys)
        tappedSinceSample.removeAll()
        let b = ps.buttons.subtracting(latchedPad)
        func k(_ c: UInt16) -> Bool { keys.contains(c) }
        return PRInput(
            up: k(Key.up) || k(Key.w) || b.contains("a") || b.contains("rt"),
            down: k(Key.down) || k(Key.s) || b.contains("b") || b.contains("lt"),
            left: k(Key.left) || k(Key.a) || b.contains("left") || b.contains("stick-left"),
            right: k(Key.right) || k(Key.d) || b.contains("right") || b.contains("stick-right"),
            boost: k(Key.space) || b.contains("x") || b.contains("rb"))
    }

    /// Text for an on-screen button prompt, matching the device in use.
    func glyph(_ a: MenuAction) -> String {
        switch device {
        case .keyboard:
            switch a {
            case .confirm: return "ENTER"
            case .back, .pause: return "ESC"
            default: return "ARROWS"
            }
        case .xbox:
            switch a {
            case .confirm: return "A"
            case .back: return "B"
            case .pause: return "MENU"
            default: return "D-PAD"
            }
        case .playStation:
            switch a {
            case .confirm: return "✕"
            case .back: return "○"
            case .pause: return "OPTIONS"
            default: return "D-PAD"
            }
        }
    }

    /// Race control hints for the start panel, matching the device in use.
    var raceHints: (accelerate: String, reverse: String, lean: String, boost: String, pause: String) {
        switch device {
        case .keyboard: return ("UP / W", "DOWN / S", "LEFT / RIGHT", "SPACE", "ESC")
        case .xbox: return ("A / RT", "B / LT", "STICK / D-PAD", "X / RB", "MENU")
        case .playStation: return ("✕ / R2", "○ / L2", "STICK / D-PAD", "□ / R1", "OPTIONS")
        }
    }
}
