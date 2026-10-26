/// How far the upload of a media sent from this device has gone.
public struct UploadProgress: Sendable, Hashable {
    public let completedBytes: Int
    public let totalBytes: Int

    /// Between 0 and 1; 0 when the total is unknown.
    public var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }

    public init(completedBytes: Int, totalBytes: Int) {
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }
}
