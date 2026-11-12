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

    /// Treadmill distance that equals one lap of lane 1, whatever this track's real lap length.
    /// Lets a non-spec model (e.g. the JG3D arena, lane 1 ≈ 390.8 m) still lap every 400 m.
    public var nominalLap: Double = 400

    public init() {}

    public init(straightLength: Double, kerbRadius: Double, laneWidth: Double, laneCount: Int = 8) {
        self.straightLength = straightLength
        self.kerbRadius = kerbRadius
        self.laneWidth = laneWidth
        self.laneCount = laneCount
    }

    public static let standard = TrackGeometry()

    /// The JG3D "Track And Field Arena" as measured in Blender (inner kerb of Track_Lanes).
    /// Not to spec: shorter straights, tighter bends, wider lanes.
    public static let jg3dArena = TrackGeometry(straightLength: 82.612, kerbRadius: 35.596, laneWidth: 1.369)

    /// Radius of the measured running line for a lane (1-based).
    public func runningRadius(lane: Int) -> Double {
        lane <= 1 ? kerbRadius + lane1Offset
                  : kerbRadius + Double(lane - 1) * laneWidth + otherLaneOffset
    }

    /// Length of one lap of the measured line for a lane. Lane 1 = 400.00 m.
    public func lapLength(lane: Int = 1) -> Double {
        2 * straightLength + 2 * .pi * runningRadius(lane: lane)
    }

    /// Middle of a lane (1-based), measured from the track centre's bend axis.
    public func laneCentreRadius(lane: Int) -> Double {
        kerbRadius + (Double(lane) - 0.5) * laneWidth
    }

    /// Where to *draw* the runner: the same progress round the lap as `pose`, but shifted out
    /// from the measuring line (0.30 m off the kerb) to the middle of the lane, so they look
    /// centred. Distance is still counted along the measuring line.
    public func displayPose(distance: Double, lane: Int = 1) -> (x: Double, y: Double, heading: Double) {
        let p = pose(distance: distance, lane: lane)
        let shift = laneCentreRadius(lane: lane) - runningRadius(lane: lane)
        // Running anticlockwise, "outwards" is to the runner's right: (sin h, -cos h).
        return (p.x + shift * sin(p.heading), p.y - shift * cos(p.heading), p.heading)
    }

    /// Position and heading for a distance run.
    /// Every `nominalLap` metres of treadmill distance is one lap of the chosen lane, so on a
    /// spec track lane 1 is 1:1, and other lanes / non-spec models are scaled to fit.
    public func pose(distance: Double, lane: Int = 1) -> (x: Double, y: Double, heading: Double) {
        let r = runningRadius(lane: lane)
        let lap = lapLength(lane: lane)
        let scaled = distance * lap / nominalLap
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
