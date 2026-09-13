import Foundation

/// État d'acheminement d'un message envoyé localement.
public enum SendState: Sendable, Hashable {
    case sending
    case sent
    case failed(reason: String)

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Message affichable dans une timeline.
public struct Message: Sendable, Hashable {
    public let eventID: EventID?
    public let sender: UserID
    public let senderDisplayName: String?
    public let body: String
    public let timestamp: Date
    public let isOwn: Bool
    public let isEdited: Bool
    public let sendState: SendState

    public init(
        eventID: EventID?,
        sender: UserID,
        senderDisplayName: String?,
        body: String,
        timestamp: Date,
        isOwn: Bool,
        isEdited: Bool,
        sendState: SendState
    ) {
        self.eventID = eventID
        self.sender = sender
        self.senderDisplayName = senderDisplayName
        self.body = body
        self.timestamp = timestamp
        self.isOwn = isOwn
        self.isEdited = isEdited
        self.sendState = sendState
    }
}

/// Élément d'une timeline : message, marqueur ou événement non pris en charge en v0.1.
public struct TimelineItem: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case message(Message)
        case redacted
        case unableToDecrypt(reason: String)
        case dateSeparator(Date)
        case readMarker
        case unsupported(description: String)
    }

    public let id: String
    public let kind: Kind

    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    /// Le message porté par cet élément, s'il s'agit d'un message.
    public var message: Message? {
        if case let .message(message) = kind { return message }
        return nil
    }
}
