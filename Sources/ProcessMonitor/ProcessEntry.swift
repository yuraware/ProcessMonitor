import Foundation

/// One row in the process table. Mirrors the columns Activity Monitor shows.
struct ProcessEntry: Identifiable, Hashable {
    /// The process id. Stable for the lifetime of the process.
    let id: pid_t
    /// The parent process id. `0` for the kernel and launchd.
    var parentID: pid_t
    var name: String
    var path: String
    var user: String
    /// Percent of a single core (so the total across processes can exceed 100).
    var cpu: Double
    /// Percent GPU. macOS does not expose per-process GPU usage through public
    /// APIs, so this is `-1` (rendered as "—") unless a source becomes available.
    var gpu: Double
    /// Physical memory footprint in bytes (same metric as Activity Monitor's Memory column).
    var memory: UInt64
    /// Approximate energy impact: CPU% plus a penalty for idle wake-ups.
    var energy: Double
    /// `false` when the process could not be inspected (typically it belongs to another user).
    var isAvailable: Bool
    /// `true` when the process is a regular application (has an `NSRunningApplication`).
    var isApp: Bool

    var pid: pid_t {
        id
    }

    var hasGPU: Bool {
        gpu >= 0
    }
}
