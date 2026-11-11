import SwiftUI
import KicksCore

/// iPhone app — the brain. Owns the treadmill connection, workouts, recording and Strava,
/// and broadcasts live state to the Apple TV. Must work fully on its own (no TV).
@main
struct KicksRideApp: App {
    var body: some Scene {
        WindowGroup { PhoneHUDView() }
    }
}

struct PhoneHUDView: View {
    // Demo mode until the FTMS port lands: a steady 12 km/h run.
    @State private var state: SessionState = { var s = SessionState(); s.speedKmh = 12; return s }()
    private let tick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 28) {
            Text("KICKS RIDE · DEMO").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            metric(Format.pace(state.paceSecondsPerKm), "min/km")
            HStack(spacing: 40) {
                metric(Format.distanceKm(state.distance), "km", size: 44)
                metric(Format.duration(state.elapsed), "time", size: 44)
            }
            Button(state.isPaused ? "Resume" : "Pause") { state.isPaused.toggle() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .monospacedDigit()
        .onReceive(tick) { _ in state.advance(by: 0.25) }
    }

    private func metric(_ value: String, _ unit: String, size: CGFloat = 96) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(size: size, weight: .bold, design: .rounded))
            Text(unit).font(.headline).foregroundStyle(.secondary)
        }
    }
}
