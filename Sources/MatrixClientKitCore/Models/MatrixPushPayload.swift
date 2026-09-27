/// The room and event a Matrix push is about, read from the notification's `userInfo`.
///
/// It reads the `room_id` and `event_id` keys at the root of the payload, where Sygnal puts them
/// for a pusher in the `event_id_only` format — the format ``NotificationService`` registers.
public struct MatrixPushPayload: Sendable, Hashable {
    public let roomID: RoomID
    public let eventID: EventID

    public init(roomID: RoomID, eventID: EventID) {
        self.roomID = roomID
        self.eventID = eventID
    }

    /// Returns `nil` when `room_id` or `event_id` is missing, is not a string, or is not a valid
    /// identifier — for instance a push that does not come from Matrix.
    public init?(userInfo: [AnyHashable: Any]) {
        guard
            let room = userInfo["room_id"] as? String,
            let roomID = RoomID(rawValue: room),
            let event = userInfo["event_id"] as? String,
            let eventID = EventID(rawValue: event)
        else { return nil }

        self.init(roomID: roomID, eventID: eventID)
    }
}
