import Foundation

/// A media written to a temporary file by ``MediaService/file(of:filename:mimeType:)``.
public protocol MediaFile: Sendable {
    /// The location of the temporary file.
    var url: URL { get }
    /// Moves the file to `destination`, so that it outlives this value. Returns false if it
    /// could not be kept.
    func persist(to destination: URL) throws -> Bool
}
