import Foundation

/// Waits for work only as long as a feature can afford: a suggestion that
/// arrives late is worth nothing, so the caller gets nil at the deadline
/// instead.
@MainActor
public enum Deadline {
    /// The result of `operation`, or nil once `budget` has passed or the
    /// calling task is cancelled. The operation is cancelled then, and this
    /// returns at the deadline even if the operation is slow to notice.
    public static func value<T: Sendable>(
        within budget: Duration,
        of operation: @escaping @MainActor () async -> T?
    ) async -> T? {
        let race = Race<T>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                race.start(continuation, budget: budget, operation: operation)
            }
        } onCancel: {
            Task { @MainActor in race.finish(nil) }
        }
    }

    /// Resumes its continuation once, with whichever comes first: the
    /// operation's result, the deadline, or the caller's cancellation.
    @MainActor
    private final class Race<T: Sendable> {
        private var continuation: CheckedContinuation<T?, Never>?
        private var tasks: [Task<Void, Never>] = []

        func start(
            _ continuation: CheckedContinuation<T?, Never>,
            budget: Duration,
            operation: @escaping @MainActor () async -> T?
        ) {
            self.continuation = continuation
            guard !Task.isCancelled, budget > .zero else { return finish(nil) }
            tasks = [
                Task { @MainActor in self.finish(await operation()) },
                Task { @MainActor in
                    try? await Task.sleep(for: budget)
                    self.finish(nil)
                },
            ]
        }

        func finish(_ value: T?) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(returning: value)
            tasks.forEach { $0.cancel() }
            tasks = []
        }
    }
}
