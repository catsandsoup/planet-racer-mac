// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlanetRacer",
    platforms: [.macOS("26.0")],
    targets: [
        // The original game's physics and race rules, ported 1:1 to C++, behind a plain C interface.
        .target(
            name: "PlanetRacerCore",
            path: "Sources/PlanetRacerCore",
            exclude: ["third_party/nlohmann/LICENSE.MIT"],
            cxxSettings: [.headerSearchPath("third_party")]
        ),
        // The Mac app: Metal rendering, SwiftUI menus, GameController input, AVFoundation audio.
        .executableTarget(
            name: "PlanetRacer",
            dependencies: ["PlanetRacerCore"],
            path: "Sources/PlanetRacer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Headless race simulator used as a physics regression test.
        .executableTarget(
            name: "RaceSim",
            dependencies: ["PlanetRacerCore"],
            path: "Sources/RaceSim"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
