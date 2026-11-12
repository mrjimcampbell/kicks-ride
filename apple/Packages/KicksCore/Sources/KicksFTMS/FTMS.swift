import CoreBluetooth
import KicksCore

/// Bluetooth service and characteristic UUIDs. Always full 128-bit form (Bluefy lesson; also what
/// CoreBluetooth reports), normalised when matching. Stored as strings because CBUUID
/// isn't Sendable under Swift 6 strict concurrency.
public enum FTMS: String, CaseIterable, Sendable {
    // Services
    case service          = "00001826-0000-1000-8000-00805F9B34FB"
    case heartRateService = "0000180D-0000-1000-8000-00805F9B34FB"
    case rscService       = "00001814-0000-1000-8000-00805F9B34FB"
    // FTMS characteristics
    case feature          = "00002ACC-0000-1000-8000-00805F9B34FB"
    case treadmillData    = "00002ACD-0000-1000-8000-00805F9B34FB"
    case indoorBikeData   = "00002AD2-0000-1000-8000-00805F9B34FB"
    case speedRange       = "00002AD4-0000-1000-8000-00805F9B34FB"
    case inclineRange     = "00002AD5-0000-1000-8000-00805F9B34FB"
    case powerRange       = "00002AD8-0000-1000-8000-00805F9B34FB"
    case controlPoint     = "00002AD9-0000-1000-8000-00805F9B34FB"
    case machineStatus    = "00002ADA-0000-1000-8000-00805F9B34FB"
    // Sensor characteristics
    case heartRateMeasurement = "00002A37-0000-1000-8000-00805F9B34FB"
    case rscMeasurement       = "00002A53-0000-1000-8000-00805F9B34FB"

    public var uuid: CBUUID { CBUUID(string: rawValue) }

    /// Matches whether CoreBluetooth reports the short ("2ACD") or full form.
    public static func from(_ uuid: CBUUID) -> FTMS? {
        let s = uuid.uuidString.uppercased()
        return allCases.first { $0.rawValue == s || $0.rawValue.dropFirst(4).prefix(4) == s }
    }

    /// Belt reports ~0.5 km/h while starting; treat anything above this as moving.
    public static let movingThresholdKmh = 0.3
}
