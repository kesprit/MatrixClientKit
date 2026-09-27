import MatrixRustSDK
import MatrixClientKitCore

/// L'événement porté par une notification amont, sous une forme qu'un test peut construire :
/// `NotificationEvent.timeline` contient un `TimelineEvent`, classe FFI, alors que son protocole
/// est implémentable.
enum NotificationEventSource {
    case timeline(any TimelineEventProtocol)
    case invite(sender: String)
}

/// Traduit les notifications et les paramètres de notification amont vers le domaine.
enum NotificationMapper {
    static let genericBody = "Sent a message"

    static func result(from status: NotificationStatus, roomID: RoomID, eventID: EventID) throws -> NotificationResult {
        switch status {
        case let .event(item):
            return .notification(try notification(from: item, roomID: roomID, eventID: eventID))
        case .eventNotFound:
            return .notFound
        case .eventFilteredOut:
            return .filteredOut
        case .eventRedacted:
            return .redacted
        }
    }

    static func notification(from item: NotificationItem, roomID: RoomID, eventID: EventID) throws -> MatrixNotification
    {
        let source: NotificationEventSource
        switch item.event {
        case let .timeline(event):
            source = .timeline(event)
        case let .invite(sender):
            source = .invite(sender: sender)
        }
        return try notification(
            source: source,
            senderInfo: item.senderInfo,
            roomInfo: item.roomInfo,
            isNoisy: item.isNoisy,
            hasMention: item.hasMention,
            threadID: item.threadId,
            roomID: roomID,
            eventID: eventID
        )
    }

    static func notification(
        source: NotificationEventSource,
        senderInfo: NotificationSenderInfo,
        roomInfo: NotificationRoomInfo,
        isNoisy: Bool?,
        hasMention: Bool?,
        threadID: String?,
        roomID: RoomID,
        eventID: EventID
    ) throws -> MatrixNotification {
        let rawSender: String
        let kind: MatrixNotification.Kind
        var rawThread = threadID

        switch source {
        case let .timeline(event):
            rawSender = event.senderId()
            rawThread = rawThread ?? event.threadRootEventId()
            let senderName = senderInfo.displayName ?? rawSender
            // Un contenu illisible ne doit pas priver l'utilisateur de la notification elle-même.
            let content = try? event.content()
            kind = .message(body: content.map { body(for: $0, senderName: senderName) } ?? genericBody)
        case let .invite(sender):
            rawSender = sender
            kind = .invite
        }

        guard let sender = UserID(rawValue: rawSender) else {
            throw MatrixError.unexpected(message: "Invalid sender in a notification: \(rawSender)", details: nil)
        }
        var thread: EventID?
        if let rawThread {
            guard let parsed = EventID(rawValue: rawThread) else {
                throw MatrixError.unexpected(message: "Invalid thread in a notification: \(rawThread)", details: nil)
            }
            thread = parsed
        }

        return MatrixNotification(
            roomID: roomID,
            eventID: eventID,
            sender: sender,
            senderDisplayName: senderInfo.displayName,
            roomDisplayName: roomInfo.displayName,
            isDirect: roomInfo.isDirect,
            kind: kind,
            isNoisy: isNoisy ?? false,
            hasMention: hasMention ?? false,
            threadID: thread
        )
    }

    static func body(for content: TimelineEventContent, senderName: String) -> String {
        guard case let .messageLike(messageLike) = content else { return genericBody }

        switch messageLike {
        case let .roomMessage(messageType, _):
            return body(for: messageType, senderName: senderName)
        case .roomEncrypted:
            return TimelineMapper.undecryptableMessage
        default:
            return genericBody
        }
    }

    /// Corps d'un message selon son type (spec 0.3, §6.1).
    static func body(for messageType: MessageType, senderName: String) -> String {
        switch messageType {
        case let .text(content):
            return content.body
        case let .notice(content):
            return content.body
        case let .emote(content):
            return "* \(senderName) \(content.body)"
        case let .image(content):
            return mediaBody(caption: content.caption, fallback: "Sent an image")
        case let .video(content):
            return mediaBody(caption: content.caption, fallback: "Sent a video")
        case let .audio(content):
            return mediaBody(caption: content.caption, fallback: "Sent an audio message")
        case let .file(content):
            return mediaBody(caption: content.caption, fallback: "Sent a file")
        case .gallery:
            return "Sent images"
        case .location:
            return "Shared a location"
        case let .other(_, body):
            // La spec Matrix impose un corps de repli à tout msgtype : c'est lui qu'il faut montrer.
            return body.isEmpty ? genericBody : body
        }
    }

    /// Légende si elle existe, sinon la phrase fixe. Le nom de fichier (souvent `IMG_1234.jpg`)
    /// n'est jamais montré.
    static func mediaBody(caption: String?, fallback: String) -> String {
        guard let caption, !caption.isEmpty else { return fallback }
        return caption
    }

    static func mode(from mode: MatrixRustSDK.RoomNotificationMode) -> MatrixClientKitCore.RoomNotificationMode {
        switch mode {
        case .allMessages: .allMessages
        case .mentionsAndKeywordsOnly: .mentionsAndKeywordsOnly
        case .mute: .mute
        }
    }

    static func upstreamMode(from mode: MatrixClientKitCore.RoomNotificationMode) -> MatrixRustSDK.RoomNotificationMode
    {
        switch mode {
        case .allMessages: .allMessages
        case .mentionsAndKeywordsOnly: .mentionsAndKeywordsOnly
        case .mute: .mute
        }
    }

    static func settings(
        from settings: MatrixRustSDK.RoomNotificationSettings
    ) -> MatrixClientKitCore.RoomNotificationSettings {
        MatrixClientKitCore.RoomNotificationSettings(mode: mode(from: settings.mode), isDefault: settings.isDefault)
    }

    static func error(from error: any Error) -> MatrixError {
        if let settingsError = error as? NotificationSettingsError, case .InvalidRoomId = settingsError {
            return .notFound(.room)
        }
        return ErrorMapper.map(error)
    }
}
