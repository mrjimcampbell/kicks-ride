import CoreBluetooth
import KicksCore

/// Fitness Machine Service UUIDs. Always full 128-bit form (Bluefy lesson; also what
/// CoreBluetooth reports), normalised when matching. Stored as strings because CBUUID
/// isn't Sendable under Swift 6 strict concurrency.
public enum FTMS: String, CaseIterable, Sendable {
    case service          = "00001826-0000-1000-8000-00805F9B34FB"
    case treadmillData    = "00002ACD-0000-1000-8000-00805F9B34FB"
    case indoorBikeData   = "00002AD2-0000-1000-8000-00805F9B34FB"
    case controlPoint     = "00002AD9-0000-1000-8000-00805F9B34FB"
    case heartRateService = "0000180D-0000-1000-8000-00805F9B34FB"
    case rscService       = "00001814-0000-1000-8000-00805F9B34FB"

    public var uuid: CBUUID { CBUUID(string: rawValue) }

    /// Belt reports ~0.5 km/h while starting; treat anything above this as moving.
    public static let movingThresholdKmh = 0.3
}

// TODO(milestone 1): port the FTMS connection, Treadmill Data parsing and serialised
// control-point writes (Set Speed 0x02, Set Incline 0x03, resend after 5 s if ignored;
// never send START to a treadmill) from index.html.
