import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Traduit les types de timeline amont vers le domaine.
enum TimelineMapper {

    /// Phrase générique d'un message indéchiffrable, partagée avec les notifications : la même
    /// situation doit se lire de la même façon dans la timeline et sur l'écran verrouillé.
    static let undecryptableMessage = "The message could not be decrypted."

    static func eventContent(
        for content: MatrixClientKitCore.MessageContent
    ) throws -> RoomMessageEventContentWithoutRelation {
        switch content {
        case let .text(body):
            do {
                return try messageEventContentNew(
                    msgtype: .text(content: TextMessageContent(body: body, formatted: nil))
                )
            } catch {
                throw ErrorMapper.map(error)
            }
        case let .markdown(body):
            return messageEventContentFromMarkdown(md: body)
        }
    }

    /// - Note: `isRecoverable` est relayé tel quel depuis l'amont, qui le définit ainsi : une
    ///   erreur récupérable désactive la file d'envoi de la room (l'envoi repartira), tandis
    ///   qu'une erreur non récupérable gare l'événement jusqu'à ce que l'utilisateur décide de
    ///   l'abandonner. C'est bien la distinction « réessayer » / « l'utilisateur doit agir »
    ///   qu'expose ``SendState/failed(reason:isRecoverable:)``.
    static func sendState(from state: EventSendState?) -> SendState {
        guard let state else { return .sent }
        switch state {
        case .notSentYet: return .sending
        case .sent: return .sent
        case let .sendingFailed(error, isRecoverable):
            return .failed(reason: reason(from: error), isRecoverable: isRecoverable)
        }
    }

    /// Traduit la cause d'un envoi bloqué en une phrase lisible.
    ///
    /// - Important: `reason` finit dans une interface. Y déverser `String(describing:)` d'un enum
    ///   amont y ferait apparaître des identifiants Swift.
    static func reason(from error: QueueWedgeError) -> String {
        switch error {
        case .insecureDevices:
            "The room contains unverified devices."
        case .identityViolations:
            "A participant's identity changed and must be verified again."
        case .crossVerificationRequired:
            "This session must be verified before it can send messages."
        case .missingMediaContent:
            "The media to send is missing from the cache."
        case let .invalidMimeType(mimeType):
            "Unsupported content type: \(mimeType)."
        case let .genericApiError(msg):
            msg.isEmpty ? "Sending failed." : msg
        }
    }

    /// Explique pourquoi un message n'a pas pu être déchiffré, à partir de la cause amont.
    ///
    /// - Note: seule la variante Megolm porte une cause ; les autres reçoivent la phrase générique.
    static func decryptionFailureReason(for message: EncryptedMessage) -> String {
        guard case let .megolmV1AesSha2(_, cause) = message else {
            return undecryptableMessage
        }

        switch cause {
        case .unknown:
            return undecryptableMessage
        case .sentBeforeWeJoined:
            return "Sent before you joined the room."
        case .verificationViolation:
            return "The sender's verified identity has changed."
        case .unsignedDevice:
            return "Sent from a device its owner has not verified."
        case .unknownDevice:
            return "Sent from an unknown device."
        case .historicalMessageAndBackupIsDisabled:
            return "Sent before this device signed in, and key backup is off."
        case .historicalMessageAndDeviceIsUnverified:
            return "Sent before this device signed in; verify this device to read it."
        case .withheldForUnverifiedOrInsecureDevice:
            return "The sender does not share keys with unverified devices."
        case .withheldBySender:
            return "The sender withheld the keys for this message."
        }
    }

    static func item(from item: MatrixRustSDK.TimelineItem) -> MatrixClientKitCore.TimelineItem {
        let id = item.uniqueId().id

        if let event = item.asEvent() {
            return MatrixClientKitCore.TimelineItem(id: id, kind: kind(from: event))
        }

        if let virtual = item.asVirtual() {
            switch virtual {
            case let .dateDivider(timestamp):
                return MatrixClientKitCore.TimelineItem(
                    id: id,
                    kind: .dateSeparator(date(from: timestamp))
                )
            case .readMarker:
                return MatrixClientKitCore.TimelineItem(id: id, kind: .readMarker)
            case .timelineStart:
                return MatrixClientKitCore.TimelineItem(
                    id: id,
                    kind: .unsupported(description: "Start of the timeline")
                )
            }
        }

        return MatrixClientKitCore.TimelineItem(
            id: id,
            kind: .unsupported(description: item.fmtDebug())
        )
    }

    private static func kind(
        from event: EventTimelineItem
    ) -> MatrixClientKitCore.TimelineItem.Kind {
        guard case let .msgLike(content) = event.content else {
            return .unsupported(description: event.eventTypeRaw ?? "Unsupported event")
        }

        switch content.kind {
        case let .message(message):
            guard let sender = UserID(rawValue: event.sender) else {
                return .unsupported(description: "Invalid sender: \(event.sender)")
            }

            return .message(
                MatrixClientKitCore.Message(
                    eventID: eventID(from: event.eventOrTransactionId),
                    sender: sender,
                    senderDisplayName: displayName(from: event.senderProfile),
                    body: message.body,
                    timestamp: date(from: event.timestamp),
                    isOwn: event.isOwn,
                    isEdited: message.isEdited,
                    sendState: sendState(from: event.localSendState)
                )
            )
        case .redacted:
            return .redacted
        case let .unableToDecrypt(msg):
            return .unableToDecrypt(reason: decryptionFailureReason(for: msg))
        case .sticker, .poll, .other, .liveLocation:
            return .unsupported(description: String(describing: content.kind))
        }
    }

    private static func eventID(from identifier: EventOrTransactionId) -> EventID? {
        switch identifier {
        case let .eventId(eventId): return EventID(rawValue: eventId)
        case .transactionId: return nil
        }
    }

    private static func displayName(from profile: ProfileDetails) -> String? {
        guard case let .ready(displayName, _, _, _, _) = profile else { return nil }
        return displayName
    }

    private static func date(from timestamp: Timestamp) -> Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    }

    /// Traduit une mise à jour de timeline amont en diff de collection du domaine.
    static func diff(from update: TimelineDiff) -> CollectionDiff<MatrixClientKitCore.TimelineItem> {
        switch update {
        case let .append(values): .append(values.map(item(from:)))
        case .clear: .clear
        case let .pushFront(value): .pushFront(item(from: value))
        case let .pushBack(value): .pushBack(item(from: value))
        case .popFront: .popFront
        case .popBack: .popBack
        case let .insert(index, value): .insert(index: Int(index), item(from: value))
        case let .set(index, value): .set(index: Int(index), item(from: value))
        case let .remove(index): .remove(index: Int(index))
        case let .truncate(length): .truncate(length: Int(length))
        case let .reset(values): .reset(values.map(item(from:)))
        }
    }
}
