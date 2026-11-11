import Foundation

/// A standard 400 m athletics track (World Athletics spec).
///
/// Coordinates are metres in the track's own plane: origin at the centre of the infield,
/// +x along the straights, +y across. The runner runs anticlockwise (bends at ±x),
/// starting at the finish line, which sits at the end of the home straight (y < 0).
public struct TrackGeometry: Sendable, Equatable {
    public var straightLength: Double = 84.39
    /// Radius of the inner kerb's bends.
    public var kerbRadius: Double = 36.5
    public var laneWidth: Double = 1.22
    public var laneCount: Int = 8
    /// Lane 1 is measured this far out from the kerb; other lanes 0.20 m from their inner line.
    public var lane1Offset: Double = 0.30
    public var otherLaneOffset: Double = 0.20

    public init() {}

    public static let standard = TrackGeometry()

    /// Radius of the measured running line for a lane (1-based).
    public func runningRadius(lane: Int) -> Double {
        lane <= 1 ? kerbRadius + lane1Offset
                  : kerbRadius + Double(lane - 1) * laneWidth + otherLaneOffset
    }

    /// Length of one lap of the measured line for a lane. Lane 1 = 400.00 m.
    public func lapLength(lane: Int = 1) -> Double {
        2 * straightLength + 2 * .pi * runningRadius(lane: lane)
    }

    /// Position and heading for a distance run.
    /// Treadmill distance is mapped 1:1 onto lane 1; for other lanes the distance is scaled so a
    /// lap still equals 400 m of treadmill distance (the runner just looks wider).
    public func pose(distance: Double, lane: Int = 1) -> (x: Double, y: Double, heading: Double) {
        let r = runningRadius(lane: lane)
        let lap = lapLength(lane: lane)
        let scaled = distance * lap / lapLength(lane: 1)
        var d = scaled.truncatingRemainder(dividingBy: lap)
        if d < 0 { d += lap }
        let half = straightLength / 2
        let bend = .pi * r

        // 1. Finish line → second half of home straight (y = -r), heading +x.
        if d < half { return (d, -r, 0) }
        d -= half
        // 2. First bend around (+half, 0).
        if d < bend { let a = -.pi / 2 + d / r; return (half + r * cos(a), r * sin(a), a + .pi / 2) }
        d -= bend
        // 3. Back straight (y = +r), heading -x.
        if d < straightLength { return (half - d, r, .pi) }
        d -= straightLength
        // 4. Second bend around (-half, 0).
        if d < bend { let a = .pi / 2 + d / r; return (-half + r * cos(a), r * sin(a), a + .pi / 2) }
        d -= bend
        // 5. First half of home straight back to the finish line.
        return (-half + d, -r, 0)
    }
}
