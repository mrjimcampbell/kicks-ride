import SwiftUI
import RealityKit
import KicksCore

/// Apple TV app — display + big HUD. Joins the phone over the local network (KicksLink).
/// For now runs a local demo session so the scene and HUD can be developed on their own.
@main
struct KicksRideTVApp: App {
    var body: some SwiftUI.Scene {
        WindowGroup { TVRootView() }
    }
}

@Observable final class TVSession {
    var state: SessionState = { var s = SessionState(); s.speedKmh = 14; return s }()
}

struct TVRootView: View {
    @State private var session = TVSession()

    var body: some View {
        // HUD at the top, over the sky, so it never covers the runner.
        ZStack(alignment: .top) {
            ArenaView(session: session)
            HStack(spacing: 80) {
                hud(Format.pace(session.state.paceSecondsPerKm), "min/km")
                hud(Format.distanceKm(session.state.distance), "km")
                hud(Format.duration(session.state.elapsed), "time")
            }
            .padding(40)
            .background(.black.opacity(0.45), in: .rect(cornerRadius: 24))
            .padding(60)
        }
        .ignoresSafeArea()
    }

    private func hud(_ value: String, _ unit: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(size: 110, weight: .bold, design: .rounded)).monospacedDigit()
            Text(unit).font(.title3).foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
    }
}
