import Foundation
import Photos
import Testing
@testable import photo_swiper

/// A value several threads can set and read.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.withLock { body(&value) }
    }
}

/// The video request resumes exactly once: with PhotoKit's answer, or nil when cancelled, even if
/// PhotoKit never calls back after a cancel (JUN-22, S-8).
struct VideoSourceTests {
    /// Polls until `condition` holds or `seconds` pass.
    private func eventually(seconds: Double = 2, _ condition: () -> Bool) async -> Bool {
        let deadline = Date.now.addingTimeInterval(seconds)
        while Date.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test func cancellingFinishesEvenIfPhotoKitNeverAnswers() async {
        let cancelled = Locked<[PHImageRequestID]>([])
        let result = Locked<String??>(nil)
        let task = Task {
            let value: String? = await VideoSource.cancellableRequest(
                start: { _ in 7 },
                cancel: { id in cancelled.withLock { $0.append(id) } }
            )
            result.withLock { $0 = .some(value) }
        }
        try? await Task.sleep(for: .milliseconds(50))

        task.cancel()

        #expect(await eventually { result.withLock { $0 } != nil }, "The request returned instead of hanging")
        #expect(result.withLock { $0 } == .some(nil))
        #expect(cancelled.withLock { $0 } == [7], "PhotoKit was asked to cancel")
    }

    @Test func theAnswerComesBackOnceEvenIfDeliveredTwice() async {
        let value: String? = await VideoSource.cancellableRequest(
            start: { handler in
                handler("first")
                handler("second")
                return 1
            },
            cancel: { _ in }
        )
        #expect(value == "first")
    }

    @Test func aCancelBeforeTheRequestStartsStillCancelsIt() async {
        let cancelled = Locked<[PHImageRequestID]>([])
        let started = Locked(false)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let value: String? = await VideoSource.cancellableRequest(
                start: { _ in
                    started.withLock { $0 = true }
                    return 3
                },
                cancel: { id in cancelled.withLock { $0.append(id) } }
            )
            return value
        }

        let value = await task.value
        #expect(value == nil)
        #expect(!started.withLock { $0 } || cancelled.withLock { $0 } == [3], "Anything started is cancelled")
    }
}
