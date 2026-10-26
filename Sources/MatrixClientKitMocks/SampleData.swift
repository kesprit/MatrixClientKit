import Foundation
import MatrixClientKitCore

/// Ready-made sample data for tests and previews.
public enum SampleData: Sendable {

    /// Builds a sample ``RoomSummary`` with sensible defaults.
    ///
    /// - Parameter membership: defaults to ``Membership/joined``. Pass another value to build a
    ///   list that a filter can meaningfully narrow — a test asserting that invitations stay out
    ///   of the main list needs at least one room that is not joined.
    public static func roomSummary(
        id: String = "!room:matrix.org",
        name: String = "Lounge",
        unread: Int = 0,
        membership: Membership = .joined
    ) -> RoomSummary {
        RoomSummary(
            id: RoomID(rawValue: id) ?? RoomID(rawValue: "!fallback:matrix.org")!,
            displayName: name,
            topic: nil,
            avatarURL: nil,
            isDirect: false,
            isEncrypted: true,
            joinedMemberCount: 4,
            notificationCount: unread,
            highlightCount: 0,
            membership: membership
        )
    }

    /// Builds `count` sample rooms with distinct identifiers and names.
    public static func roomSummaries(
        count: Int,
        membership: Membership = .joined
    ) -> [RoomSummary] {
        (0..<count).map { index in
            roomSummary(id: "!room\(index):matrix.org", name: "Lounge \(index)", membership: membership)
        }
    }

    /// Builds a sample ``TimelineItem`` carrying a message.
    public static func message(
        _ body: String,
        from sender: String = "@alice:matrix.org",
        isOwn: Bool = false
    ) -> TimelineItem {
        TimelineItem(
            id: UUID().uuidString,
            kind: .message(
                Message(
                    eventID: EventID(rawValue: "$\(UUID().uuidString)"),
                    sender: UserID(rawValue: sender) ?? UserID(rawValue: "@unknown:matrix.org")!,
                    senderDisplayName: nil,
                    body: body,
                    timestamp: Date(),
                    isOwn: isOwn,
                    isEdited: false,
                    sendState: .sent
                )
            )
        )
    }

    /// Builds a sample ``MediaSource`` at `mxc://example.org/<id>`.
    public static func mediaSource(_ id: String = "media") -> MediaSource {
        MediaSource(url: "mxc://example.org/\(id)")!
    }

    /// Builds a sample ``MediaAttachment`` of the given kind, with a plausible file name and
    /// MIME type for it.
    public static func mediaAttachment(
        kind: MediaAttachment.Kind = .image,
        source: MediaSource = mediaSource(),
        filename: String? = nil,
        caption: String? = nil,
        size: Int? = 2048,
        dimensions: MediaDimensions? = nil
    ) -> MediaAttachment {
        let (defaultName, mimeType): (String, String) = switch kind {
        case .image: ("photo.jpg", "image/jpeg")
        case .video: ("clip.mp4", "video/mp4")
        case .audio: ("song.mp3", "audio/mpeg")
        case .voice: ("voice.ogg", "audio/ogg")
        case .file: ("document.pdf", "application/pdf")
        }
        return MediaAttachment(
            kind: kind,
            source: source,
            filename: filename ?? defaultName,
            caption: caption,
            mimeType: mimeType,
            size: size,
            dimensions: dimensions ?? (kind == .image || kind == .video ? MediaDimensions(width: 640, height: 480) : nil)
        )
    }

    /// Builds a sample image ``Attachment`` from bytes in memory.
    public static func imageAttachment(filename: String = "photo.jpg") -> Attachment {
        Attachment(
            source: .data(Data([0xFF, 0xD8, 0xFF]), filename: filename),
            kind: .image(dimensions: MediaDimensions(width: 640, height: 480), blurhash: nil),
            mimeType: "image/jpeg"
        )
    }

    /// Builds a sample ``TimelineItem`` carrying a media message. The body is the caption, or the
    /// file name when there is none.
    public static func imageMessage(
        _ media: MediaAttachment = mediaAttachment(),
        from sender: String = "@alice:matrix.org",
        isOwn: Bool = false,
        uploadProgress: UploadProgress? = nil
    ) -> TimelineItem {
        TimelineItem(
            id: UUID().uuidString,
            kind: .message(
                Message(
                    eventID: EventID(rawValue: "$\(UUID().uuidString)"),
                    sender: UserID(rawValue: sender) ?? UserID(rawValue: "@unknown:matrix.org")!,
                    senderDisplayName: nil,
                    body: media.caption ?? media.filename,
                    timestamp: Date(),
                    isOwn: isOwn,
                    isEdited: false,
                    sendState: .sent,
                    media: media,
                    uploadProgress: uploadProgress
                )
            )
        )
    }

    /// Builds a sample ``MatrixNotification`` from Alice in the "Lounge" room.
    public static func notification(
        kind: MatrixNotification.Kind = .message(body: "Hello"),
        isDirect: Bool = false,
        isNoisy: Bool = true
    ) -> MatrixNotification {
        MatrixNotification(
            roomID: RoomID(rawValue: "!room:matrix.org")!,
            eventID: EventID(rawValue: "$event")!,
            sender: UserID(rawValue: "@alice:matrix.org")!,
            senderDisplayName: "Alice",
            roomDisplayName: "Lounge",
            isDirect: isDirect,
            kind: kind,
            isNoisy: isNoisy,
            hasMention: false,
            threadID: nil
        )
    }

    /// Builds a sample ``PusherConfiguration`` pointing at a gateway on `example.com`.
    public static func pusherConfiguration() -> PusherConfiguration {
        PusherConfiguration(
            deviceToken: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            appID: "com.example.app.ios.dev",
            gatewayURL: URL(string: "https://push.example.com/_matrix/push/v1/notify")!,
            appDisplayName: "Example",
            deviceDisplayName: "iPhone",
            language: "en"
        )
    }

    /// Builds ``LoginDetails`` for a password-only homeserver by default.
    public static func loginDetails(
        homeserver: URL = URL(string: "https://matrix.example.org")!,
        supportsPassword: Bool = true,
        supportsOAuth: Bool = false,
        oauthPrompts: Set<OAuthPrompt> = []
    ) -> LoginDetails {
        LoginDetails(
            homeserver: homeserver,
            supportsPassword: supportsPassword,
            supportsOAuth: supportsOAuth,
            supportsSSO: false,
            oauthPrompts: oauthPrompts
        )
    }

    /// A ready-made ``OAuthConfiguration`` for `com.example.app`.
    public static func oauthConfiguration() -> OAuthConfiguration {
        OAuthConfiguration(
            clientName: "Example",
            redirectURI: URL(string: "com.example.app:/callback")!,
            clientURI: URL(string: "https://example.com")!
        )
    }
}
