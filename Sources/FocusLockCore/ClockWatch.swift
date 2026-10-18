import Foundation

/// Notices system clock changes by comparing the wall clock with a monotonic clock
/// that keeps counting during sleep, so moving the clock forward can't end a block early.
public struct ClockWatch: Sendable {
    private var lastWall: Date
    private var lastReal: UInt64

    public init(wall: Date = Date(), real: UInt64 = ClockWatch.realNanos()) {
        lastWall = wall
        lastReal = real
    }

    /// Nanoseconds of real time, including sleep (CLOCK_MONOTONIC on Darwin).
    public static func realNanos() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_MONOTONIC)
    }

    /// How far the wall clock moved beyond real elapsed time since the previous call.
    public mutating func skew(wall: Date = Date(), real: UInt64 = ClockWatch.realNanos()) -> TimeInterval {
        let wallDelta = wall.timeIntervalSince(lastWall)
        let realDelta = Double(real &- lastReal) / 1_000_000_000
        lastWall = wall
        lastReal = real
        return wallDelta - realDelta
    }
}
