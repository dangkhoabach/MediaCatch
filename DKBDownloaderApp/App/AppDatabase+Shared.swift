import DKBDownloaderCore
import Foundation

/// How `AppDatabase.shared` had to recover on this launch, if at all —
/// surfaced once by `AppDelegate` so an unexpectedly empty history reads as
/// "here's what happened and where the old file went" instead of silent data
/// loss.
enum DatabaseRecovery {
    case replacedUnopenableFile(backupPath: String)
    case inMemoryFallback
}

/// One shared connection for the whole app's lifetime, instead of every
/// view model/manager opening its own separate `AppDatabase(path:)` to the
/// same file — GRDB's `ValueObservation` only re-fires for writes made
/// through the *same* `DatabaseQueue` instance it was created from, and
/// DKB Monitor hit a real bug from skipping this (see Mục 1.5 in
/// docs/swift-native-port-plan.md). Established here at Phase 6, the first
/// point an App-layer type (`MenuBarStatsViewModel`) needs its own DB
/// access, rather than waiting for the bug to actually appear.
extension AppDatabase {
    /// Non-optional on purpose: callers would otherwise force-unwrap it,
    /// turning an unopenable database file into a crash on every launch with
    /// no way for the user to recover.
    static let shared: AppDatabase = openOrRecover()

    /// Only written inside `shared`'s lazy initializer (which Swift runs
    /// exactly once), read afterwards.
    private(set) nonisolated(unsafe) static var recovery: DatabaseRecovery?

    private static func openOrRecover() -> AppDatabase {
        let path = AppDatabaseLocation.productionPath().path
        if let database = try? AppDatabase(path: path) { return database }

        // Couldn't open the existing file. Move it aside rather than delete
        // it — it may still be salvageable by hand — and start fresh.
        let backupPath = path + ".corrupt-\(Int(Date().timeIntervalSince1970))"
        try? FileManager.default.moveItem(atPath: path, toPath: backupPath)
        if let database = try? AppDatabase(path: path) {
            recovery = .replacedUnopenableFile(backupPath: backupPath)
            return database
        }

        // Can't write to Application Support at all (a full disk, say).
        // In-memory keeps this session usable; `try!` because building an
        // in-memory database touches no filesystem and has nothing to fail on.
        recovery = .inMemoryFallback
        return try! AppDatabase.inMemory()
    }
}
