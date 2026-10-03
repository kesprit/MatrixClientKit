import Foundation
import MatrixClientKitCore

/// A drivable ``QRCodeLogin``. Push states with ``emit(_:)``; ``start()`` returns or throws
/// ``startResult``.
public final class MockQRCodeLogin: QRCodeLogin, @unchecked Sendable {
    private let lock = NSLock()
    private var current: QRCodeLoginState = .starting
    private var continuations: [UUID: AsyncStream<QRCodeLoginState>.Continuation] = [:]
    private var _startResult: Result<MockMatrixSession, MatrixError>
    private var _submittedCheckCodes: [UInt8] = []
    private var _submitError: MatrixError?
    private var _didCancel = false

    public init(startResult: Result<MockMatrixSession, MatrixError> = .success(MockMatrixSession())) {
        self._startResult = startResult
    }

    /// What ``start()`` returns or throws.
    public var startResult: Result<MockMatrixSession, MatrixError> {
        get { lock.withLock { _startResult } }
        set { lock.withLock { _startResult = newValue } }
    }

    /// The error ``submitCheckCode(_:)`` throws. `nil` by default.
    public var submitError: MatrixError? {
        get { lock.withLock { _submitError } }
        set { lock.withLock { _submitError = newValue } }
    }

    /// Every code passed to ``submitCheckCode(_:)``, in order — including rejected ones.
    public var submittedCheckCodes: [UInt8] { lock.withLock { _submittedCheckCodes } }

    /// True once ``cancel()`` has been called.
    public var didCancel: Bool { lock.withLock { _didCancel } }

    /// Like the real login, starts with the current state, then every ``emit(_:)``.
    public var state: AsyncStream<QRCodeLoginState> {
        let (stream, continuation) = AsyncStream<QRCodeLoginState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        lock.withLock {
            continuation.yield(current)
            continuations[id] = continuation
        }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { _ = self.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    /// Pushes a state to every subscriber of ``state``.
    public func emit(_ state: QRCodeLoginState) {
        lock.withLock {
            current = state
            for continuation in continuations.values { continuation.yield(state) }
        }
    }

    public func start() async throws -> any MatrixSession {
        if lock.withLock({ _didCancel }) {
            throw CancellationError()
        }
        return try startResult.get()
    }

    public func submitCheckCode(_ code: UInt8) async throws {
        let error = lock.withLock {
            _submittedCheckCodes.append(code)
            return _submitError
        }
        if let error { throw error }
    }

    public func cancel() {
        let continuationsToUpdate = lock.withLock {
            _didCancel = true
            current = .failed(.cancelled)
            return continuations.values.map { $0 }
        }
        for continuation in continuationsToUpdate {
            continuation.yield(.failed(.cancelled))
        }
    }
}
