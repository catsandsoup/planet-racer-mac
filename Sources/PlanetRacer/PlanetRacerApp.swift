import SwiftUI

@main
struct PlanetRacerApp: App {
    @State private var model = GameModel()

    var body: some Scene {
        Window("Planet Racer", id: "main") {
            ZStack {
                MetalView(model: model)
                OverlayView(model: model)
            }
            .frame(minWidth: 640, minHeight: 400)
            .background(Color.black)
            .onAppear {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate()
                // restore full screen once the window exists
                DispatchQueue.main.async { model.applyFullscreen() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
                if model.settings.fullscreen { model.settings.fullscreen = false; model.save() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
                if !model.settings.fullscreen { model.settings.fullscreen = true; model.save() }
            }
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            // the menu bar only calls the in-game settings screen; it never keeps its own copy
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.openSettings() }.keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {}
        }
    }
}
