import Foundation
import UIKit

/// When the indexer may run: in the foreground, outside Low Power Mode, and while the device is cool.
enum IndexGate {
    static func canRun(isForeground: Bool, isLowPower: Bool, thermal: ProcessInfo.ThermalState) -> Bool {
        isForeground && !isLowPower && (thermal == .nominal || thermal == .fair)
    }
}

/// Starts the library indexer once photo access is granted and pauses it when it shouldn't run.
///
/// Pausing cancels the run; the indexer's work queue is rebuilt from what's stored, so the next run
/// resumes without redoing anything. A run is due at access and on every return to the foreground,
/// which picks up photos taken since. Removals reported by the library are forwarded as they happen.
/// Foreground only for now: no background tasks.
@MainActor
final class IndexScheduler {
    private let indexer: LibraryIndexer
    private let library: any PhotoLibraryProviding
    private var hasAccess = false
    private var isForeground = true
    /// A run is wanted and hasn't finished since it was asked for.
    private var isDue = false
    private var task: Task<Void, Never>?
    private var runID = 0
    private var vanishedTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(indexer: LibraryIndexer, library: any PhotoLibraryProviding) {
        self.indexer = indexer
        self.library = library
    }

    /// Call once access is anything but denied. Later calls do nothing.
    func accessGranted() {
        guard !hasAccess else { return }
        hasAccess = true
        isDue = true
        isForeground = UIApplication.shared.applicationState != .background
        observe()
        let vanished = library.vanishedItems()
        vanishedTask = Task { [indexer] in
            for await ids in vanished { await indexer.remove(ids) }
        }
        update()
    }

    private func update() {
        let info = ProcessInfo.processInfo
        let allowed = hasAccess && IndexGate.canRun(isForeground: isForeground, isLowPower: info.isLowPowerModeEnabled, thermal: info.thermalState)
        if !allowed {
            task?.cancel()
            task = nil
        } else if isDue, task == nil {
            runID += 1
            let id = runID
            task = Task(priority: .utility) { [indexer, weak self] in
                await indexer.run()
                self?.runEnded(id, cancelled: Task.isCancelled)
            }
        }
    }

    private func runEnded(_ id: Int, cancelled: Bool) {
        guard id == runID else { return }
        task = nil
        if !cancelled { isDue = false }
    }

    private func observe() {
        let center = NotificationCenter.default
        let on = { [weak self] (name: Notification.Name, change: @escaping @MainActor (IndexScheduler) -> Void) in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    change(self)
                    self.update()
                }
            }
        }
        observers = [
            on(UIApplication.didEnterBackgroundNotification) { $0.isForeground = false },
            on(UIApplication.willEnterForegroundNotification) { $0.isForeground = true; $0.isDue = true },
            on(.NSProcessInfoPowerStateDidChange) { _ in },
            on(ProcessInfo.thermalStateDidChangeNotification) { _ in },
        ]
    }
}
