import Foundation

/// A media written to a temporary file by ``MediaService/file(of:filename:mimeType:)``.
public protocol MediaFile: Sendable {
    /// The location of the temporary file.
    ///
    /// Once ``persist(to:)`` returned `true`, this URL is stale: the file lives at the
    /// destination you passed.
    var url: URL { get }
    /// Moves the file to `destination`, so that it outlives this value. Returns false if it
    /// could not be kept. After a move, read the file at `destination`, no longer at ``url``.
    func persist(to destination: URL) throws -> Bool
}
