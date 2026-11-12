// swift-tools-version: 6.2
import PackageDescription

// Shared code for the iPhone (brain) and Apple TV (display) apps.
// Kept platform-neutral where possible so roles can later be swapped
// (e.g. the TV driving the treadmill on its own).
let package = Package(
    name: "KicksCore",
    platforms: [.iOS(.v26), .tvOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KicksCore", targets: ["KicksCore"]),
        .library(name: "KicksFTMS", targets: ["KicksFTMS"]),
        .library(name: "KicksLink", targets: ["KicksLink"]),
        .library(name: "KicksRecording", targets: ["KicksRecording"]),
    ],
    targets: [
        // Pure Swift: units, pace, workouts, live session state, 400 m track geometry.
        .target(name: "KicksCore"),
        // CoreBluetooth: FTMS treadmill / bike, heart-rate strap, footpod.
        .target(name: "KicksFTMS", dependencies: ["KicksCore"]),
        // Network.framework + Bonjour: phone <-> TV live-state messages.
        .target(name: "KicksLink", dependencies: ["KicksCore"]),
        // TCX writer + Strava upload via the existing Cloudflare relay.
        .target(name: "KicksRecording", dependencies: ["KicksCore"]),
        .testTarget(name: "KicksCoreTests", dependencies: ["KicksCore", "KicksLink", "KicksFTMS"]),
    ]
)
