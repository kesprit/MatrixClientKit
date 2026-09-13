/// Contenu d'un message à envoyer. La v0.1 couvre le texte ; les médias arrivent en v0.4.
public enum MessageContent: Sendable, Hashable {
    /// Texte brut, sans mise en forme.
    case text(String)
    /// Texte au format Markdown, à rendre côté affichage.
    case markdown(String)

    /// Corps textuel brut, utilisable comme repli d'affichage.
    public var plainBody: String {
        switch self {
        case let .text(body): return body
        case let .markdown(body): return body
        }
    }
}
