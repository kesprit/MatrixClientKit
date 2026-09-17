import Foundation
import MatrixClientKitCore

/// A drivable ``SessionVerification``.
///
/// It runs no state machine: your test decides every state with ``emit(_:)``, and checks the
/// commands your code called with ``calls``.
public final class MockSessionVerification: SessionVerification, @unchecked Sendable {
    /// A command of ``SessionVerification``.
    public enum Command: Sendable, Hashable {
        case requestVerification
        case accept
        case startSAS
        case approve
        case decline
        case cancel
    }

    private let lock = NSLock()
    private let stream: AsyncStream<SessionVerificationState>
    private let continuation: AsyncStream<SessionVerificationState>.Continuation

    private var _calls: [Command] = []
    private var _errors: [Command: MatrixError] = [:]

    public init() {
        (stream, continuation) = AsyncStream<SessionVerificationState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    public var state: AsyncStream<SessionVerificationState> { stream }

    /// Every command called so far, in order — including those that threw.
    public var calls: [Command] { lock.withLock { _calls } }

    /// Makes `command` throw `error`; pass `nil` to make it succeed again.
    public func setError(_ error: MatrixError?, for command: Command) {
        lock.withLock { _errors[command] = error }
    }

    /// Pushes a state to ``state``.
    public func emit(_ state: SessionVerificationState) {
        continuation.yield(state)
    }

    /// Ends ``state``.
    public func finish() {
        continuation.finish()
    }

    public func requestVerification() async throws { try record(.requestVerification) }
    public func accept() async throws { try record(.accept) }
    public func startSAS() async throws { try record(.startSAS) }
    public func approve() async throws { try record(.approve) }
    public func decline() async throws { try record(.decline) }
    public func cancel() async throws { try record(.cancel) }

    private func record(_ command: Command) throws {
        let error = lock.withLock {
            _calls.append(command)
            return _errors[command]
        }
        if let error { throw error }
    }
}
