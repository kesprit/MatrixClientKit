/// A media being uploaded by ``Timeline/send(_:)``.
public protocol AttachmentUpload: Sendable {
    /// Stops the upload while it is being prepared, before it is queued; its local echo then
    /// never appears, or is removed.
    ///
    /// Once the media is queued, this has no effect: cancel or retry it through
    /// ``Timeline/sendHandle(for:)`` on its local echo. Only the first call has an effect.
    func cancel()
    /// Returns once the media is in the send queue and its local echo is in ``Timeline/items`` —
    /// not once it is sent: follow the echo's ``Message/sendState`` for that.
    ///
    /// Throws `CancellationError` if ``cancel()`` was called before that. Cancellation wins: a
    /// ``cancel()`` arriving right after the media was queued still makes this throw
    /// `CancellationError`, although the upload goes on — cancel it through
    /// ``Timeline/sendHandle(for:)``.
    func waitUntilQueued() async throws
}
