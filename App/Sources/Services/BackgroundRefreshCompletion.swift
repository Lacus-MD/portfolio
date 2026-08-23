import BackgroundTasks
import Foundation

/// Guarantees that an iOS background task is completed exactly once, even if
/// expiration races with the async work finishing.
final class BackgroundRefreshCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didComplete = false
    private let task: BGTask

    init(task: BGTask) { self.task = task }

    func finish(success: Bool) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        lock.unlock()
        task.setTaskCompleted(success: success)
    }
}
