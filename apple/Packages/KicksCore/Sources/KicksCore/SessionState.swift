import Foundation

/// The live state the phone (brain) broadcasts and the TV (display) renders.
/// Kept small and Codable so it can go over the local network several times a second.
public struct SessionState: Codable, Sendable, Equatable {
    public enum Activity: String, Codable, Sendable { case run, ride }

    public var activity: Activity = .run
    public var elapsed: TimeInterval = 0
    /// Metres since the session started (drives the runner around the track).
    public var distance: Double = 0
    public var speedKmh: Double = 0
    public var inclinePercent: Double = 0
    public var heartRate: Int?
    public var cadence: Int?
    public var powerWatts: Int?
    public var isPaused: Bool = false
    /// Current workout block, if a workout is playing, e.g. "Rep 3/6 · 400 m @ 4:00/km".
    public var blockTitle: String?
    public var blockRemaining: TimeInterval?

    public init() {}

    /// Integrate speed over a time step (used by demo mode and as a fallback when the
    /// treadmill doesn't report total distance).
    public mutating func advance(by dt: TimeInterval) {
        guard !isPaused else { return }
        elapsed += dt
        distance += speedKmh / 3.6 * dt
    }

    /// Pace in seconds per km, or nil when (nearly) stopped.
    public var paceSecondsPerKm: Double? {
        speedKmh > 0.3 ? 3600 / speedKmh : nil
    }
}

public enum Format {
    /// "4:05" style min:sec per km.
    public static func pace(_ secondsPerKm: Double?) -> String {
        guard let s = secondsPerKm, s.isFinite else { return "–:––" }
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    public static func duration(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    public static func distanceKm(_ metres: Double) -> String {
        String(format: "%.2f", metres / 1000)
    }
}
