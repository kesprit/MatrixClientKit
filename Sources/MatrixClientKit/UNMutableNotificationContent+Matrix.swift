#if canImport(UserNotifications)
    import UserNotifications
    import MatrixClientKitCore

    extension UNMutableNotificationContent {
        /// Fills the title, body, thread identifier and sound from a resolved notification.
        ///
        /// A direct conversation is titled with the sender; any other room with its name, the body
        /// then starting with the sender's name. Notifications are grouped by room, and play the
        /// default sound only when the user's push rules ask for one. Everything else — badge,
        /// attachments, user info — is left untouched.
        public func apply(_ notification: MatrixNotification) {
            let senderName = notification.senderDisplayName ?? notification.sender.rawValue

            switch notification.kind {
            case let .message(body):
                title = notification.isDirect ? senderName : notification.roomDisplayName
                self.body = notification.isDirect ? body : "\(senderName): \(body)"
            case .invite:
                title = notification.isDirect ? senderName : notification.roomDisplayName
                body = "Invited you to chat"
            }

            threadIdentifier = notification.roomID.rawValue
            sound = notification.isNoisy ? .default : nil
        }
    }
#endif
