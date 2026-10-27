/// How far the upload of a media sent from this device has gone.
public struct UploadProgress: Sendable, Hashable {
    /// The bytes uploaded so far.
    public let completedBytes: Int
    /// The bytes to upload in all; 0 when unknown.
    public let totalBytes: Int

    /// Between 0 and 1; 0 when the total is unknown.
    public var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }

    /// Builds a progress from the bytes uploaded so far and the total.
    public init(completedBytes: Int, totalBytes: Int) {
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }
}
