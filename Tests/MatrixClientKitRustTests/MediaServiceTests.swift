import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private struct ThumbnailCall: Equatable {
    let url: String
    let width: UInt64
    let height: UInt64
}

private struct FileCall: Equatable {
    let url: String
    let filename: String?
    let mimeType: String
    let useCache: Bool
    let tempDir: String?
}

private final class FakeHandle: MediaFileHandleDriving, @unchecked Sendable {
    let location: String
    private let lock = NSLock()
    private var _persisted: [String] = []
    var persisted: [String] { lock.withLock { _persisted } }
    var persistResult = true

    init(location: String) { self.location = location }

    func path() throws -> String { location }
    func persist(path: String) throws -> Bool {
        lock.withLock { _persisted.append(path) }
        return persistResult
    }
}

private final class FakeMediaDriver: MediaDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var _contentURLs: [String] = []
    private var _thumbnails: [ThumbnailCall] = []
    private var _files: [FileCall] = []
    var error: (any Error)?
    var maxSize: UInt64 = 0
    let handle = FakeHandle(location: "/tmp/matrix/photo.jpg")

    var contentURLs: [String] { lock.withLock { _contentURLs } }
    var thumbnails: [ThumbnailCall] { lock.withLock { _thumbnails } }
    var files: [FileCall] { lock.withLock { _files } }
    var callCount: Int { lock.withLock { _contentURLs.count + _thumbnails.count + _files.count } }

    func getMediaContent(mediaSource: MatrixRustSDK.MediaSource) async throws -> Data {
        try lock.withLock {
            if let error { throw error }
            _contentURLs.append(mediaSource.url())
        }
        return Data([1, 2, 3])
    }

    func getMediaThumbnail(
        mediaSource: MatrixRustSDK.MediaSource, width: UInt64, height: UInt64
    ) async throws -> Data {
        try lock.withLock {
            if let error { throw error }
            _thumbnails.append(ThumbnailCall(url: mediaSource.url(), width: width, height: height))
        }
        return Data([4])
    }

    func getMediaFile(
        mediaSource: MatrixRustSDK.MediaSource, filename: String?, mimeType: String, useCache: Bool, tempDir: String?
    ) async throws -> any MediaFileHandleDriving {
        try lock.withLock {
            if let error { throw error }
            _files.append(
                FileCall(
                    url: mediaSource.url(), filename: filename, mimeType: mimeType, useCache: useCache,
                    tempDir: tempDir))
        }
        return handle
    }

    func getMaxMediaUploadSize() async throws -> UInt64 {
        if let error { throw error }
        return maxSize
    }
}

private let plain = MatrixClientKitCore.MediaSource(url: "mxc://e/a")!

private func apiError(_ kind: ErrorKind) -> ClientError {
    .MatrixApi(kind: kind, code: "M_X", msg: "boom", details: nil)
}

@Suite struct MediaServiceTests {
    private func makeService(_ driver: FakeMediaDriver) -> RustMediaService {
        RustMediaService(driver: driver, lifetime: .detached())
    }

    @Test func contentPassesSource() async throws {
        let driver = FakeMediaDriver()
        let data = try await makeService(driver).content(of: plain)
        #expect(data == Data([1, 2, 3]))
        #expect(driver.contentURLs == ["mxc://e/a"])
    }

    @Test func thumbnailPassesDimensions() async throws {
        let driver = FakeMediaDriver()
        _ = try await makeService(driver).thumbnail(of: plain, width: 320, height: 200)
        #expect(driver.thumbnails == [ThumbnailCall(url: "mxc://e/a", width: 320, height: 200)])
    }

    @Test func thumbnailClampsNonPositiveDimensions() async throws {
        let driver = FakeMediaDriver()
        _ = try await makeService(driver).thumbnail(of: plain, width: 0, height: -5)
        #expect(driver.thumbnails == [ThumbnailCall(url: "mxc://e/a", width: 1, height: 1)])
    }

    @Test func notFoundBecomesMedia() async {
        let driver = FakeMediaDriver()
        driver.error = apiError(.notFound)
        let service = makeService(driver)
        await #expect(throws: MatrixError.notFound(.media)) { try await service.content(of: plain) }
        await #expect(throws: MatrixError.notFound(.media)) {
            try await service.file(of: plain, filename: nil, mimeType: "image/png")
        }
    }

    @Test func tooLargeIsExplicitUnexpected() async {
        let driver = FakeMediaDriver()
        driver.error = apiError(.tooLarge)
        let service = makeService(driver)
        await #expect(
            throws: MatrixError.unexpected(message: "The media is larger than the homeserver accepts.", details: "M_X")
        ) { try await service.content(of: plain) }
    }

    @Test func otherErrorsUseErrorMapper() async {
        let driver = FakeMediaDriver()
        driver.error = apiError(.forbidden)
        let service = makeService(driver)
        await #expect(throws: MatrixError.permission(.forbidden)) { try await service.maxUploadSize() }
    }

    @Test func fileExposesPathAndPersists() async throws {
        let driver = FakeMediaDriver()
        let file = try await makeService(driver).file(of: plain, filename: "photo.jpg", mimeType: "image/jpeg")
        #expect(file.url == URL(fileURLWithPath: "/tmp/matrix/photo.jpg"))
        #expect(
            driver.files == [
                FileCall(url: "mxc://e/a", filename: "photo.jpg", mimeType: "image/jpeg", useCache: true, tempDir: nil)
            ])
        let kept = try file.persist(to: URL(fileURLWithPath: "/tmp/kept/photo.jpg"))
        #expect(kept)
        #expect(driver.handle.persisted == ["/tmp/kept/photo.jpg"])
    }

    @Test func maxUploadSizeClamps() async throws {
        let driver = FakeMediaDriver()
        driver.maxSize = UInt64.max
        #expect(try await makeService(driver).maxUploadSize() == Int.max)
        driver.maxSize = 52_428_800
        #expect(try await makeService(driver).maxUploadSize() == 52_428_800)
    }

    @Test func encryptedSourceWithoutJSONFailsBeforeDriver() async {
        let driver = FakeMediaDriver()
        let lost = MatrixClientKitCore.MediaSource(url: "mxc://e/a", isEncrypted: true, upstreamJSON: nil)
        let service = makeService(driver)
        await #expect(throws: MatrixError.self) { try await service.content(of: lost) }
        await #expect(throws: MatrixError.self) { try await service.thumbnail(of: lost, width: 1, height: 1) }
        await #expect(throws: MatrixError.self) {
            try await service.file(of: lost, filename: nil, mimeType: "image/png")
        }
        #expect(driver.callCount == 0)
    }
}
