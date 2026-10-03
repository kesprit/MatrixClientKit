import MatrixClientKitCore

/// Ce qu'un utilisateur tape dans le champ « serveur » d'un écran de connexion.
enum ServerInput {
    /// Rend une chaîne acceptée par `serverNameOrHomeserverUrl` : nom de serveur ou URL.
    ///
    /// Un user ID est réduit à son nom de serveur — l'amont propose `serverNameFromUserId`, mais
    /// une seule entrée de builder garde le chemin unique. Une saisie vide est rejetée ici, sans
    /// appel réseau.
    static func normalize(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") {
            guard let colon = trimmed.firstIndex(of: ":") else { throw invalid(input) }
            let server = String(trimmed[trimmed.index(after: colon)...])
            guard !server.isEmpty else { throw invalid(input) }
            return server
        }
        guard !trimmed.isEmpty else { throw invalid(input) }
        return trimmed
    }

    private static func invalid(_ input: String) -> MatrixError {
        .unexpected(message: "Enter a server name, a homeserver URL or a user ID.", details: input)
    }
}
