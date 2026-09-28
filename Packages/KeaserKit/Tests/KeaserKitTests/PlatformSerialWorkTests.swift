import Foundation
import Testing
@testable import KeaserKit

/// Holds a job until the test opens it: a stand-in for a call into a system
/// service that stalls.
@MainActor
private final class Latch {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

@MainActor
struct PlatformSerialWorkTests {
    @Test func jobsRunOneAtATimeInTheOrderStarted() async {
        let work = SerialWork()
        var log: [String] = []
        work.start {
            log.append("first starts")
            try? await Task.sleep(for: .milliseconds(80))
            log.append("first ends")
        }
        let second = work.start { log.append("second") }
        await second.value
        #expect(log == ["first starts", "first ends", "second"])
    }

    @Test func aQuickJobIsWaitedFor() async {
        let work = SerialWork()
        var done = false
        let finished = await work.run(within: .seconds(5)) { done = true }
        #expect(finished)
        #expect(done)
    }

    @Test func aStalledJobDoesNotHoldTheCallerPastItsBudget() async {
        let work = SerialWork()
        let latch = Latch()
        var log: [String] = []
        let clock = ContinuousClock()
        let started = clock.now
        let finished = await work.run(within: .milliseconds(100)) {
            await latch.wait()
            log.append("stalled job ends")
        }
        #expect(!finished)
        #expect(clock.now - started < .seconds(2))
        #expect(log.isEmpty)

        // The job was not cancelled: it ends once the service answers, and
        // the next one still runs after it.
        let next = work.start { log.append("next") }
        latch.open()
        await next.value
        #expect(log == ["stalled job ends", "next"])
    }

    @Test func performWaitsItsTurnAndHandsBackTheResult() async throws {
        struct Refused: Error {}
        let work = SerialWork()
        var log: [String] = []
        work.start {
            try? await Task.sleep(for: .milliseconds(80))
            log.append("earlier")
        }
        let value = try await work.perform { () -> Int in
            log.append("asked")
            return 42
        }
        #expect(value == 42)
        #expect(log == ["earlier", "asked"])
        await #expect(throws: Refused.self) {
            try await work.perform { () -> Int in throw Refused() }
        }
        // A job that threw does not hold up the next one.
        await work.start { log.append("after") }.value
        #expect(log.last == "after")
    }

    @Test func requestsWhileAJobWaitsShareIt() async {
        let work = SerialWork()
        let latch = Latch()
        var runs = 0
        // A slow job holds the queue; everything asked meanwhile joins one
        // waiting job, which then runs once.
        work.start { await latch.wait() }
        let first = work.startOrJoin { runs += 1 }
        let second = work.startOrJoin { runs += 1 }
        let finished = await work.runOrJoin(within: .milliseconds(50)) { runs += 1 }
        #expect(!finished)
        latch.open()
        await first.value
        await second.value
        #expect(runs == 1)
        // Once it has begun, the next request queues a new one.
        #expect(await work.runOrJoin(within: .seconds(5)) { runs += 1 })
        #expect(runs == 2)
    }

    @Test func aJobThatHasBegunIsNotJoined() async {
        let work = SerialWork()
        let latch = Latch()
        var log: [String] = []
        let running = work.startOrJoin {
            log.append("first begins")
            await latch.wait()
        }
        try? await Task.sleep(for: .milliseconds(50))
        let next = work.startOrJoin { log.append("second") }
        latch.open()
        await running.value
        await next.value
        #expect(log == ["first begins", "second"])
    }

    @Test func aCancelledCallerStopsWaitingButTheJobRuns() async {
        let work = SerialWork()
        let latch = Latch()
        var ended = false
        let caller = Task { @MainActor in
            await work.run(within: .seconds(30)) {
                await latch.wait()
                ended = true
            }
        }
        try? await Task.sleep(for: .milliseconds(50))
        caller.cancel()
        #expect(await caller.value == false)
        latch.open()
        await work.start {}.value
        #expect(ended)
    }
}
