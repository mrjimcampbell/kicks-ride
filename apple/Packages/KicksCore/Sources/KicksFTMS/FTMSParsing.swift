import Foundation

// Pure decoders/encoders for the Bluetooth fitness profiles. No CoreBluetooth here, so it's all
// unit-testable with captured byte packets. Ported from the web app (index.html), plus a few
// fields it skipped (treadmill total distance, elapsed time).

/// Little-endian byte reader that fails softly (returns nil) on short packets.
struct ByteReader {
    let bytes: [UInt8]
    private(set) var offset = 0
    init(_ data: Data) { bytes = [UInt8](data) }
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var remaining: Int { bytes.count - offset }

    mutating func u8() -> UInt8? {
        guard remaining >= 1 else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }
    mutating func u16() -> UInt16? {
        guard remaining >= 2 else { return nil }
        defer { offset += 2 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }
    mutating func s16() -> Int16? { u16().map { Int16(bitPattern: $0) } }
    mutating func u24() -> UInt32? {
        guard remaining >= 3 else { return nil }
        defer { offset += 3 }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16
    }
    mutating func u32() -> UInt32? {
        guard remaining >= 4 else { return nil }
        defer { offset += 4 }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
    mutating func skip(_ n: Int) -> Bool {
        guard remaining >= n else { return false }
        offset += n
        return true
    }
}

// MARK: - Treadmill Data (0x2ACD)

public struct TreadmillData: Equatable, Sendable {
    public var speedKmh: Double?
    public var totalDistance: Double?     // metres, since the treadmill's session started
    public var inclinePercent: Double?
    public var heartRate: Int?
    public var elapsed: TimeInterval?

    public init(speedKmh: Double? = nil, totalDistance: Double? = nil, inclinePercent: Double? = nil,
                heartRate: Int? = nil, elapsed: TimeInterval? = nil) {
        self.speedKmh = speedKmh; self.totalDistance = totalDistance
        self.inclinePercent = inclinePercent; self.heartRate = heartRate; self.elapsed = elapsed
    }

    /// Fields appear in flag-bit order; any field we don't use is skipped by its size.
    public static func parse(_ data: Data) -> TreadmillData? {
        var r = ByteReader(data)
        guard let f = r.u16() else { return nil }
        var t = TreadmillData()
        if f & 0x0001 == 0 { guard let v = r.u16() else { return t }; t.speedKmh = Double(v) / 100 }
        if f & 0x0002 != 0 { guard r.skip(2) else { return t } }                       // average speed
        if f & 0x0004 != 0 { guard let v = r.u24() else { return t }; t.totalDistance = Double(v) }
        if f & 0x0008 != 0 {                                                             // incline + ramp angle
            guard let v = r.s16(), r.skip(2) else { return t }
            if v != 0x7FFF { t.inclinePercent = Double(v) / 10 }
        }
        if f & 0x0010 != 0 { guard r.skip(4) else { return t } }                       // elevation gain +/-
        if f & 0x0020 != 0 { guard r.skip(1) else { return t } }                       // instantaneous pace
        if f & 0x0040 != 0 { guard r.skip(1) else { return t } }                       // average pace
        if f & 0x0080 != 0 { guard r.skip(5) else { return t } }                       // expended energy
        if f & 0x0100 != 0 { guard let v = r.u8() else { return t }; if v > 0 { t.heartRate = Int(v) } }
        if f & 0x0200 != 0 { guard r.skip(1) else { return t } }                       // metabolic equivalent
        if f & 0x0400 != 0 { guard let v = r.u16() else { return t }; t.elapsed = TimeInterval(v) }
        return t
    }
}

// MARK: - Indoor Bike Data (0x2AD2)

public struct IndoorBikeData: Equatable, Sendable {
    public var speedKmh: Double?          // the trainer's own speed estimate
    public var cadence: Double?           // rpm
    public var totalDistance: Double?     // metres
    public var power: Int?                // watts
    public var heartRate: Int?
    public var elapsed: TimeInterval?

    public init() {}

    public static func parse(_ data: Data) -> IndoorBikeData? {
        var r = ByteReader(data)
        guard let f = r.u16() else { return nil }
        var b = IndoorBikeData()
        if f & 0x0001 == 0 { guard let v = r.u16() else { return b }; b.speedKmh = Double(v) / 100 }
        if f & 0x0002 != 0 { guard r.skip(2) else { return b } }                       // average speed
        if f & 0x0004 != 0 { guard let v = r.u16() else { return b }; b.cadence = Double(v) / 2 }
        if f & 0x0008 != 0 { guard r.skip(2) else { return b } }                       // average cadence
        if f & 0x0010 != 0 { guard let v = r.u24() else { return b }; b.totalDistance = Double(v) }
        if f & 0x0020 != 0 { guard r.skip(2) else { return b } }                       // resistance level
        if f & 0x0040 != 0 { guard let v = r.s16() else { return b }; b.power = max(0, Int(v)) }
        if f & 0x0080 != 0 { guard r.skip(2) else { return b } }                       // average power
        if f & 0x0100 != 0 { guard r.skip(5) else { return b } }                       // expended energy
        if f & 0x0200 != 0 { guard let v = r.u8() else { return b }; if v > 0 { b.heartRate = Int(v) } }
        if f & 0x0400 != 0 { guard r.skip(1) else { return b } }                       // metabolic equivalent
        if f & 0x0800 != 0 { guard let v = r.u16() else { return b }; b.elapsed = TimeInterval(v) }
        return b
    }
}

// MARK: - Heart Rate Measurement (0x2A37)

public enum HeartRateMeasurement {
    public static func parse(_ data: Data) -> Int? {
        var r = ByteReader(data)
        guard let f = r.u8() else { return nil }
        let bpm = f & 0x01 != 0 ? r.u16().map(Int.init) : r.u8().map(Int.init)
        guard let bpm, bpm > 0 else { return nil }
        return bpm
    }
}

// MARK: - Running Speed and Cadence (0x2A53), e.g. a footpod

public struct RSCMeasurement: Equatable, Sendable {
    public var speedKmh: Double
    /// Steps per minute. Some footpods report strides/min (half); doubled when clearly running.
    public var cadence: Int
    public var isRunning: Bool?

    public static func parse(_ data: Data) -> RSCMeasurement? {
        var r = ByteReader(data)
        guard let f = r.u8(), let speed = r.u16(), let cad = r.u8() else { return nil }
        let kmh = Double(speed) / 256 * 3.6
        var steps = Int(cad)
        if steps > 0, steps < 120, kmh > 5 { steps *= 2 }
        return RSCMeasurement(speedKmh: kmh, cadence: steps, isRunning: f & 0x04 != 0 ? true : nil)
    }
}

// MARK: - Ranges (0x2AD4 speed, 0x2AD5 incline, 0x2AD8 power)

public struct SupportedRange: Equatable, Sendable {
    public var min: Double, max: Double, step: Double

    /// Speed: uint16 ×0.01 km/h.
    public static func speed(_ data: Data) -> SupportedRange? {
        var r = ByteReader(data)
        guard let lo = r.u16(), let hi = r.u16(), let st = r.u16() else { return nil }
        return SupportedRange(min: Double(lo) / 100, max: Double(hi) / 100, step: Double(st) / 100)
    }
    /// Incline: sint16 ×0.1 %, step uint16 ×0.1 %.
    public static func incline(_ data: Data) -> SupportedRange? {
        var r = ByteReader(data)
        guard let lo = r.s16(), let hi = r.s16(), let st = r.u16() else { return nil }
        return SupportedRange(min: Double(lo) / 10, max: Double(hi) / 10, step: Swift.max(0.1, Double(st) / 10))
    }
    /// Power: sint16 W, step uint16 W.
    public static func power(_ data: Data) -> SupportedRange? {
        var r = ByteReader(data)
        guard let lo = r.s16(), let hi = r.s16(), let st = r.u16() else { return nil }
        return SupportedRange(min: Double(lo), max: Double(hi), step: Double(st))
    }

    public func clamp(_ v: Double) -> Double { Swift.min(max, Swift.max(min, v)) }
}

// MARK: - Fitness Machine Control Point (0x2AD9) and Status (0x2ADA)

public enum ControlPoint {
    public enum OpCode: UInt8, Sendable {
        case requestControl = 0x00, reset = 0x01, setSpeed = 0x02, setIncline = 0x03
        case setResistance = 0x04, setPower = 0x05, start = 0x07, stop = 0x08
        case setSimulation = 0x11, response = 0x80

        public var label: String {
            switch self {
            case .requestControl: "request control"
            case .reset: "reset"
            case .setSpeed: "target speed"
            case .setIncline: "target incline"
            case .setResistance: "resistance"
            case .setPower: "ERG target"
            case .start: "start"
            case .stop: "stop"
            case .setSimulation: "gradient"
            case .response: "response"
            }
        }
    }

    public enum Result: UInt8, Sendable {
        case success = 1, notSupported = 2, invalidParameter = 3, failed = 4, controlNotPermitted = 5
        public var label: String {
            switch self {
            case .success: "ok"
            case .notSupported: "not supported"
            case .invalidParameter: "invalid parameter"
            case .failed: "failed"
            case .controlNotPermitted: "control not permitted"
            }
        }
    }

    public struct Response: Equatable, Sendable {
        public var request: OpCode
        public var result: Result
    }

    public static func requestControl() -> Data { Data([OpCode.requestControl.rawValue]) }
    /// Never send to a treadmill — the runner starts the belt themselves.
    public static func start() -> Data { Data([OpCode.start.rawValue]) }
    /// Stop (0x01) rather than pause (0x02). Safe for a treadmill: it only ever slows the belt.
    public static func stop() -> Data { Data([OpCode.stop.rawValue, 0x01]) }
    public static func pause() -> Data { Data([OpCode.stop.rawValue, 0x02]) }

    public static func setSpeed(kmh: Double) -> Data {
        let v = UInt16(clamping: Int((kmh * 100).rounded()))
        return Data([OpCode.setSpeed.rawValue, UInt8(v & 0xFF), UInt8(v >> 8)])
    }
    public static func setIncline(percent: Double) -> Data {
        let v = UInt16(bitPattern: Int16(clamping: Int((percent * 10).rounded())))
        return Data([OpCode.setIncline.rawValue, UInt8(v & 0xFF), UInt8(v >> 8)])
    }
    public static func setTargetPower(watts: Int) -> Data {
        let v = UInt16(bitPattern: Int16(clamping: watts))
        return Data([OpCode.setPower.rawValue, UInt8(v & 0xFF), UInt8(v >> 8)])
    }
    /// Simulation: wind 0 m/s, grade in %, rolling resistance Crr, wind resistance Cw (kg/m).
    public static func setSimulation(gradePercent: Double, crr: Double, cw: Double) -> Data {
        let g = UInt16(bitPattern: Int16(clamping: Int((gradePercent * 100).rounded())))
        return Data([OpCode.setSimulation.rawValue, 0, 0,
                     UInt8(g & 0xFF), UInt8(g >> 8),
                     UInt8(clamping: Int((crr * 10000).rounded())),
                     UInt8(clamping: Int((cw * 100).rounded()))])
    }

    public static func parseResponse(_ data: Data) -> Response? {
        var r = ByteReader(data)
        guard r.u8() == OpCode.response.rawValue,
              let req = r.u8().flatMap(OpCode.init(rawValue:)),
              let res = r.u8().flatMap(Result.init(rawValue:)) else { return nil }
        return Response(request: req, result: res)
    }
}

public enum MachineStatus: Equatable, Sendable {
    case stoppedOrPaused, started, controlLost, other(UInt8)

    public static func parse(_ data: Data) -> MachineStatus? {
        guard let c = data.first else { return nil }
        switch c {
        case 0x02: return .stoppedOrPaused
        case 0x04: return .started
        case 0xFF: return .controlLost
        default: return .other(c)
        }
    }
}
