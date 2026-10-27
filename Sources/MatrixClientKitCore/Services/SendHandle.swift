/// Controls a message sent from this device, while it is still a local echo.
public protocol SendHandle: Sendable {
    /// Cancels the send if the message has not left yet; the local echo is removed.
    /// Returns false when it was already sent. Only the first call has an effect.
    @discardableResult func cancel() async throws -> Bool
    /// Sends again a message whose send failed, once the cause is fixed.
    func retry() async throws
}
