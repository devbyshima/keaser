import Foundation

/// Jobs that must run one at a time, in the order they were started, each
/// one seeing what the one before it did: Spotlight writes, and the weekly
/// summary's reschedules.
///
/// A caller that cannot wait long, such as an App Intent the system may
/// suspend as soon as it returns, waits for its job only up to a budget. The
/// job is not cancelled then: it finishes on its own, and the jobs started
/// after it still wait for it.
@MainActor
public final class SerialWork {
    private var last: Task<Void, Never>?
    /// A job from `startOrJoin(_:)` that has not begun yet.
    private var waiting: Task<Void, Never>?

    public init() {}

    /// Starts `job` once every job started before it has finished, and
    /// returns right away with the task running it.
    @discardableResult
    public func start(_ job: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = last
        let task = Task { @MainActor in
            await previous?.value
            await job()
        }
        last = task
        return task
    }

    /// `start(_:)` for jobs that are all the same and read the latest state
    /// when they begin, such as rescheduling the weekly summary: while one
    /// such job is still waiting for its turn, this returns it instead of
    /// queueing another, so requests made while a slow job runs cost one
    /// more job, not one each.
    @discardableResult
    public func startOrJoin(_ job: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        if let waiting { return waiting }
        let task = start { [weak self] in
            self?.waiting = nil
            await job()
        }
        waiting = task
        return task
    }

    /// Runs `job` once every job started before it has finished, and
    /// returns what it returns (or throws what it throws), however long it
    /// takes.
    public func perform<T: Sendable>(_ job: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = last
        let task = Task { @MainActor () async throws -> T in
            await previous?.value
            return try await job()
        }
        last = Task { @MainActor in _ = try? await task.value }
        return try await task.value
    }

    /// Starts `job` like `start(_:)`, then waits for it: true when it
    /// finished within `budget`, false when the budget ran out first or the
    /// caller was cancelled.
    @discardableResult
    public func run(within budget: Duration, _ job: @escaping @MainActor () async -> Void) async -> Bool {
        await wait(for: start(job), within: budget)
    }

    /// `run(within:_:)` through `startOrJoin(_:)`.
    @discardableResult
    public func runOrJoin(within budget: Duration, _ job: @escaping @MainActor () async -> Void) async -> Bool {
        await wait(for: startOrJoin(job), within: budget)
    }

    private func wait(for task: Task<Void, Never>, within budget: Duration) async -> Bool {
        // Waiting on a task's value ignores cancellation, so the deadline is
        // raced beside it rather than cancelling it.
        await Deadline.value(within: budget) { () -> Bool? in
            await task.value
            return true
        } ?? false
    }
}
