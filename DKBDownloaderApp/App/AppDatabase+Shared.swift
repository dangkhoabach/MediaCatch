import DKBDownloaderCore

/// One shared connection for the whole app's lifetime, instead of every
/// view model/manager opening its own separate `AppDatabase(path:)` to the
/// same file — GRDB's `ValueObservation` only re-fires for writes made
/// through the *same* `DatabaseQueue` instance it was created from, and
/// DKB Monitor hit a real bug from skipping this (see Mục 1.5 in
/// docs/swift-native-port-plan.md). Established here at Phase 6, the first
/// point an App-layer type (`MenuBarStatsViewModel`) needs its own DB
/// access, rather than waiting for the bug to actually appear.
extension AppDatabase {
    static let shared: AppDatabase? = try? AppDatabase(path: AppDatabaseLocation.productionPath().path)
}
