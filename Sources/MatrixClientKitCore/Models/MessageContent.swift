/// The content of a message to send. v0.1 covers text; media arrives in v0.5.
public enum MessageContent: Sendable, Hashable {
    /// Plain text, with no formatting.
    case text(String)
    /// Markdown text, to be rendered by the display layer.
    case markdown(String)

    /// The raw text body, usable as a display fallback.
    public var plainBody: String {
        switch self {
        case let .text(body): return body
        case let .markdown(body): return body
        }
    }
}
