/// A media being uploaded by ``Timeline/send(_:)``.
public protocol AttachmentUpload: Sendable {
    /// Stops the upload if it has not finished; the local echo is removed.
    func cancel()
    /// Returns once the media is sent. Throws `CancellationError` after ``cancel()``.
    ///
    /// Cancellation wins: a ``cancel()`` arriving right after the upload finished still makes this
    /// throw `CancellationError`.
    func waitUntilSent() async throws
}
