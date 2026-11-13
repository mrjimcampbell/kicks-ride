import Foundation
import KicksCore

/// Bonjour service type advertised by the phone and browsed by the TV.
/// Must match NSBonjourServices in both apps' Info.plist.
public let kicksBonjourType = "_kicksride._tcp"

/// Messages exchanged between phone and TV. JSON, one per framed message.
public enum LinkMessage: Codable, Sendable, Equatable {
    /// Phone → TV, about once a second during a run (the TV smooths in between).
    case state(SessionState)
    /// Phone → TV: no run in progress (app open, or the run just ended). TV goes back to idle.
    case idle
    /// TV → phone (Siri Remote / ring remote presses on the TV side).
    case command(Command)
    /// TV → phone: the TV's current look and test settings (on connect, on any change, and
    /// about once a second with its frame rate). Drives the phone's TV test-controller page.
    case tvStatus(TVStatus)
    /// Phone → TV: apply these settings (the whole set, edited from the latest `tvStatus`).
    case tvSet(TVSettings)

    public enum Command: String, Codable, Sendable {
        case pause, resume, skipBlock, snapshot, speedUp, speedDown, end
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> LinkMessage {
        try JSONDecoder().decode(LinkMessage.self, from: data)
    }
}

/// Look-dev / test variables of a TV display, switched from the phone instead of the remote.
/// Option values are plain strings so the TV owns the lists (it reports them in `TVStatus`) and
/// the phone needs no update when a TV gains a camera or weather. Every field is required: the
/// Unity TV app decodes with JsonUtility, which has no optionals.
public struct TVSettings: Codable, Sendable, Equatable {
    public var time: String              // e.g. "Night"
    public var weather: String           // e.g. "Rain"
    public var camera: String            // e.g. "Standard", "Orbit"
    /// Idle only: the runner laps as a screensaver.
    public var screensaver: Bool
    /// Screensaver speed, km/h; 0 = the built-in programme of changing speeds.
    public var screensaverSpeed: Double
    /// Name of the TV's quality level (one of `TVStatus.qualityLevels`).
    public var quality: String
    /// 0 dry … 1 full puddles. Grows while it rains and dries afterwards unless held.
    /// In `tvSet`, −1 = leave it as it is (it drifts, so a stale value would pull it back).
    public var wetness: Double
    public var holdWetness: Bool
    /// Multipliers on the mood's own values (1 = as designed).
    public var volumetric: Double
    public var fog: Double
    public var showFPS: Bool

    public init(time: String = "Night", weather: String = "Clear", camera: String = "Orbit",
                screensaver: Bool = false, screensaverSpeed: Double = 0, quality: String = "",
                wetness: Double = 0, holdWetness: Bool = false, volumetric: Double = 1,
                fog: Double = 1, showFPS: Bool = false) {
        self.time = time; self.weather = weather; self.camera = camera
        self.screensaver = screensaver; self.screensaverSpeed = screensaverSpeed
        self.quality = quality; self.wetness = wetness; self.holdWetness = holdWetness
        self.volumetric = volumetric; self.fog = fog; self.showFPS = showFPS
    }
}

public struct TVStatus: Codable, Sendable, Equatable {
    public var tvName: String
    public var settings: TVSettings
    /// Choices for the string settings, as the TV knows them.
    public var times: [String]
    public var weathers: [String]
    public var cameras: [String]
    public var qualityLevels: [String]
    /// Frames per second, averaged over the last second.
    public var fps: Double
    /// A phone run is showing (screensaver doesn't apply).
    public var running: Bool

    public init(tvName: String, settings: TVSettings, times: [String], weathers: [String],
                cameras: [String], qualityLevels: [String], fps: Double, running: Bool) {
        self.tvName = tvName; self.settings = settings; self.times = times; self.weathers = weathers
        self.cameras = cameras; self.qualityLevels = qualityLevels; self.fps = fps; self.running = running
    }
}
