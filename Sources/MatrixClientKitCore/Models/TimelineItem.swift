import Foundation

/// État d'acheminement d'un message envoyé localement.
public enum SendState: Sendable, Hashable {
    /// Le message est en cours d'envoi vers le homeserver.
    case sending
    /// Le homeserver a accepté le message.
    case sent
    /// L'envoi a échoué ; `reason` décrit la cause.
    ///
    /// - Parameters:
    ///   - reason: cause de l'échec, rédigée pour être lisible. Diagnostic : une application qui
    ///     localise son interface doit produire son propre texte plutôt que d'afficher celui-ci.
    ///   - isRecoverable: l'envoi peut être réessayé **tel quel**, typiquement une fois la
    ///     connectivité revenue, par opposition à un échec que l'utilisateur doit d'abord
    ///     résoudre (vérifier sa session, retirer un appareil non vérifié, choisir un autre
    ///     média). C'est la distinction sur laquelle une interface décide d'offrir « réessayer »
    ///     ou « abandonner l'envoi ».
    case failed(reason: String, isRecoverable: Bool)

    /// Vrai si l'envoi a échoué.
    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    /// Vrai si l'envoi a échoué et peut être réessayé tel quel ; `false` dans tous les autres cas,
    /// y compris lorsque l'envoi n'a pas échoué.
    public var isRecoverableFailure: Bool {
        if case let .failed(_, isRecoverable) = self { return isRecoverable }
        return false
    }
}

/// Message affichable dans une timeline.
public struct Message: Sendable, Hashable {
    /// Identifiant de l'événement une fois acheminé par le homeserver, `nil` tant qu'il est local.
    public let eventID: EventID?
    /// Identifiant de l'expéditeur.
    public let sender: UserID
    /// Nom d'affichage de l'expéditeur au moment de l'envoi, s'il est connu.
    public let senderDisplayName: String?
    /// Corps textuel du message.
    public let body: String
    /// Horodatage du message.
    public let timestamp: Date
    /// Vrai si le message a été envoyé par l'utilisateur courant.
    public let isOwn: Bool
    /// Vrai si le message a été modifié depuis son envoi initial.
    public let isEdited: Bool
    /// État d'acheminement du message.
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
        /// Un message affichable.
        case message(Message)
        /// Un événement dont le contenu a été supprimé (modération, retrait par son auteur).
        case redacted
        /// Un événement chiffré que le client n'a pas pu déchiffrer ; `reason` en donne la cause.
        case unableToDecrypt(reason: String)
        /// Un séparateur visuel marquant un changement de jour.
        case dateSeparator(Date)
        /// Le marqueur de la dernière lecture de la room par l'utilisateur courant.
        case readMarker
        /// Un événement d'un type reconnu mais non pris en charge par l'affichage en v0.1.
        case unsupported(description: String)
    }

    /// Identité stable de l'élément au sein de la timeline, utilisée pour le diffing d'une
    /// liste affichée. Ce n'est pas un identifiant d'événement Matrix : un élément sans
    /// événement associé (séparateur, marqueur de lecture) en a un tout de même.
    public let id: String
    /// Contenu de l'élément.
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
