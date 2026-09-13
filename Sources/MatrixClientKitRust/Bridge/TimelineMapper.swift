import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Traduit les types de timeline amont vers le domaine.
enum TimelineMapper {

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

    /// - Note: `EventSendState.sendingFailed` porte aussi `isRecoverable`, la seule information
    ///   réellement actionable (réessayer, ou demander à l'utilisateur d'abandonner l'envoi).
    ///   ``SendState/failed(reason:)`` ne sait pas la transporter : l'ajouter changerait la
    ///   signature d'un cas d'enum public. Le point est remonté à la revue plutôt que tranché
    ///   ici ; en attendant, le drapeau est perdu.
    static func sendState(from state: EventSendState?) -> SendState {
        guard let state else { return .sent }
        switch state {
        case .notSentYet: return .sending
        case .sent: return .sent
        case let .sendingFailed(error, _): return .failed(reason: reason(from: error))
        }
    }

    /// Traduit la cause d'un envoi bloqué en une phrase lisible.
    ///
    /// - Important: `reason` finit dans une interface. Y déverser `String(describing:)` d'un enum
    ///   amont y ferait apparaître des identifiants Swift.
    private static func reason(from error: QueueWedgeError) -> String {
        switch error {
        case .insecureDevices:
            "des appareils non vérifiés sont présents dans la room"
        case .identityViolations:
            "l'identité d'un participant a changé et doit être vérifiée à nouveau"
        case .crossVerificationRequired:
            "cette session doit être vérifiée avant de pouvoir envoyer des messages"
        case .missingMediaContent:
            "le média à envoyer est introuvable dans le cache"
        case let .invalidMimeType(mimeType):
            "type de contenu non pris en charge : \(mimeType)"
        case let .genericApiError(msg):
            msg.isEmpty ? "l'envoi a échoué" : msg
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
                    kind: .unsupported(description: "début de timeline")
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
            return .unsupported(description: event.eventTypeRaw ?? "événement non pris en charge")
        }

        switch content.kind {
        case let .message(message):
            guard let sender = UserID(rawValue: event.sender) else {
                return .unsupported(description: "expéditeur invalide : \(event.sender)")
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
        case .unableToDecrypt:
            return .unableToDecrypt(reason: "message chiffré non déchiffrable")
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
