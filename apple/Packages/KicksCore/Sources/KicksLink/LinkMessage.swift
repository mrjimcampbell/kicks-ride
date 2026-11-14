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
    /// Frame cap: one of `TVStatus.frameRates` (the display's refresh rate or half).
    public var frameRate: Int
    /// Realism switches: one of `TVStatus.ambientOcclusionModes` / `antiAliasingModes`.
    public var ambientOcclusion: String
    public var antiAliasing: String
    /// Lens effects.
    public var lensDirt: Bool
    public var vignette: Bool
    public var filmGrain: Bool
    public var chromaticAberration: Bool
    /// Full-screen card for matching TVs' brightness/contrast.
    public var calibration: Bool
    /// 3D render scale override, 0 = the quality tier's own; above 1 = supersampling.
    public var renderScale: Double

    public init(time: String = "Night", weather: String = "Clear", camera: String = "Orbit",
                screensaver: Bool = false, screensaverSpeed: Double = 0, quality: String = "",
                wetness: Double = 0, holdWetness: Bool = false, volumetric: Double = 1,
                fog: Double = 1, showFPS: Bool = false, frameRate: Int = 60,
                ambientOcclusion: String = "", antiAliasing: String = "", lensDirt: Bool = false,
                vignette: Bool = true, filmGrain: Bool = false, chromaticAberration: Bool = false,
                calibration: Bool = false, renderScale: Double = 0) {
        self.time = time; self.weather = weather; self.camera = camera
        self.screensaver = screensaver; self.screensaverSpeed = screensaverSpeed
        self.quality = quality; self.wetness = wetness; self.holdWetness = holdWetness
        self.volumetric = volumetric; self.fog = fog; self.showFPS = showFPS
        self.frameRate = frameRate
        self.ambientOcclusion = ambientOcclusion; self.antiAliasing = antiAliasing
        self.lensDirt = lensDirt; self.vignette = vignette; self.filmGrain = filmGrain
        self.chromaticAberration = chromaticAberration; self.calibration = calibration
        self.renderScale = renderScale
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
    public var ambientOcclusionModes: [String]
    public var antiAliasingModes: [String]
    /// Frames per second, averaged over the last second.
    public var fps: Double
    /// A phone run is showing (screensaver doesn't apply).
    public var running: Bool
    /// Output size and the 3D render size, e.g. "3840×2160 · 3D 3072×1728".
    public var resolution: String
    /// Frame caps the display allows: its refresh rate and half (50/25 at 50 Hz, 60/30 at 60 Hz).
    public var frameRates: [Int]
    public var refreshRate: Double

    public init(tvName: String, settings: TVSettings, times: [String], weathers: [String],
                cameras: [String], qualityLevels: [String], ambientOcclusionModes: [String] = [], antiAliasingModes: [String] = [],
                fps: Double, running: Bool, resolution: String = "", frameRates: [Int] = [60, 30],
                refreshRate: Double = 60) {
        self.tvName = tvName; self.settings = settings; self.times = times; self.weathers = weathers
        self.cameras = cameras; self.qualityLevels = qualityLevels; self.fps = fps; self.running = running
        self.resolution = resolution
        self.frameRates = frameRates; self.refreshRate = refreshRate
        self.ambientOcclusionModes = ambientOcclusionModes; self.antiAliasingModes = antiAliasingModes
    }
}
