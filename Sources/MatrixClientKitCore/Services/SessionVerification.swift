import Foundation

/// Verifies this device against another of the user's devices, by comparing short authentication
/// strings (SAS).
///
/// The flow is published as a state machine: observe ``state`` and call the command the current
/// state allows. A command called in a state that does not allow it throws
/// ``MatrixError/unexpected(message:details:)`` and does nothing.
///
/// Only one verification runs at a time. A request received while a flow is in progress is
/// ignored.
public protocol SessionVerification: Sendable {
    /// A stream of the flow's state, starting with the current value. Every access opens an
    /// independent subscription.
    var state: AsyncStream<SessionVerificationState> { get }

    /// Asks the user's other devices to verify this one.
    /// Allowed in ``SessionVerificationState/idle`` and after a finished flow.
    func requestVerification() async throws

    /// Accepts the incoming request. Allowed in ``SessionVerificationState/incomingRequest(_:)``.
    func accept() async throws

    /// Starts comparing short authentication strings. Allowed in ``SessionVerificationState/ready``.
    func startSAS() async throws

    /// Confirms that both devices show the same strings.
    /// Allowed in ``SessionVerificationState/comparing(_:)``.
    func approve() async throws

    /// Reports that the strings differ, which cancels the flow.
    /// Allowed in ``SessionVerificationState/comparing(_:)``.
    func decline() async throws

    /// Cancels the flow in progress, or declines an incoming request.
    func cancel() async throws
}
