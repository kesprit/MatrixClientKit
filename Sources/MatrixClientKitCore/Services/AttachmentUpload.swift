/// A media being uploaded by ``Timeline/send(_:)``.
public protocol AttachmentUpload: Sendable {
    /// Stops the upload if it has not finished; the local echo is removed.
    func cancel()
    /// Returns once the media is sent. Throws `CancellationError` after ``cancel()``.
    func waitUntilSent() async throws
}
