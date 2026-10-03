import Testing
import Foundation

// Noms relevés sur les pages de MAS 1.26.0 (version épinglée du harnais). Aucun formulaire de MAS
// ne porte d'attribut `action` utile : chacun se soumet à l'URL de sa page.

/// Jeton anti-CSRF caché dans chaque formulaire.
private let csrfField = "csrf"
private let usernameField = "username"
private let passwordField = "password"
/// Code d'appareil saisi sur `/link` (RFC 8628, « user code »).
private let userCodeField = "code"
/// Case « c'est bien mon appareil » et bouton d'approbation de `/device/<id>`.
private let confirmDeviceField = "confirm_device"
private let actionField = "action"
private let consentAction = "consent"

/// Page de connexion : `/login?kind=…&id=…`.
private let loginPath = "/login"
/// Consentement d'une autorisation OAuth : `/consent/<id>`.
private let consentPathPrefix = "/consent/"
/// Saisie du code d'appareil : `/link`.
private let linkPath = "/link"
/// Consentement d'un code d'appareil : `/device/<id>`.
private let devicePathPrefix = "/device/"
/// Titre de la page qui conclut une approbation d'appareil, en anglais : le pilote impose la
/// langue (`Accept-Language`), sans quoi MAS suit celle du système.
private let deviceGrantedTitle = "Access granted"
/// API GraphQL de MAS, celle qu'appelle sa page de compte, authentifiée par le cookie de session.
private let graphQLPath = "graphql"

/// Pilote les formulaires web de Matrix Authentication Service par HTTP, comme le ferait un
/// utilisateur dans le navigateur : connexion, consentement OAuth, approbation d'un code d'appareil.
///
/// Chaque pilote a son propre stockage de cookies (session éphémère) : deux pilotes ne partagent
/// jamais de session MAS. Aucune redirection n'est suivie automatiquement : le pilote les suit
/// lui-même pour s'arrêter sur celle qui vise le schéma de l'application.
struct MASDriver {
    private let mas: URL
    private let session: URLSession

    init(mas: URL) {
        self.mas = mas
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpAdditionalHeaders = ["Accept-Language": "en"]
        session = URLSession(configuration: configuration)
    }

    /// Ouvre `url` (la page d'autorisation), se connecte, consent, et rend l'URL de rappel vers
    /// `redirectScheme`, à passer à ``OAuthLoginFlow/complete(callbackURL:)``.
    func authorize(_ url: URL, username: String, password: String, redirectScheme: String) async throws -> URL {
        var page = try await open(url, redirectScheme: redirectScheme)
        var loginSubmitted = false
        // Connexion puis consentement : quelques étapes suffisent, la borne évite une boucle.
        for _ in 0..<6 {
            switch page {
            case let .callback(callback):
                return callback
            case let .page(pageURL, html):
                let fields: [(String, String)]
                if pageURL.path == loginPath {
                    // La page de connexion revenue après l'envoi : MAS a refusé, et dit pourquoi.
                    guard !loginSubmitted else {
                        throw MASDriverError("MAS refused the sign-in", url: pageURL, html: html)
                    }
                    loginSubmitted = true
                    fields = [(usernameField, username), (passwordField, password)]
                } else if pageURL.path.hasPrefix(consentPathPrefix) {
                    fields = []
                } else {
                    throw MASDriverError("unexpected page during authorization", url: pageURL, html: html)
                }
                page = try await submit(fields, on: pageURL, html: html, redirectScheme: redirectScheme)
            }
        }
        throw MASDriverError("authorization did not reach the \(redirectScheme) callback", url: url, html: nil)
    }

    /// Se connecte et approuve la connexion d'un nouvel appareil (RFC 8628) ouverte à
    /// `verificationURI`. `userCode` n'est saisi que si MAS le demande : une URI « complète » le
    /// porte déjà.
    func approveDevice(verificationURI: URL, userCode: String?, username: String, password: String) async throws {
        var page = try await open(verificationURI, redirectScheme: nil)
        var loginSubmitted = false
        for _ in 0..<6 {
            guard case let .page(pageURL, html) = page else {
                throw MASDriverError("unexpected redirection during device approval", url: verificationURI, html: nil)
            }
            if pageURL.path == linkPath {
                guard let userCode else {
                    throw MASDriverError("MAS asks for the user code, none was given", url: pageURL, html: html)
                }
                page = try await submit([(userCodeField, userCode)], on: pageURL, html: html, redirectScheme: nil)
            } else if pageURL.path == loginPath {
                guard !loginSubmitted else {
                    throw MASDriverError("MAS refused the sign-in", url: pageURL, html: html)
                }
                loginSubmitted = true
                page = try await submit(
                    [(usernameField, username), (passwordField, password)], on: pageURL, html: html,
                    redirectScheme: nil)
            } else if pageURL.path.hasPrefix(devicePathPrefix) {
                // Après l'approbation, la même page n'a plus de formulaire de consentement et
                // annonce l'accès accordé : c'est la fin attendue.
                guard html.contains("name=\"\(confirmDeviceField)\"") else {
                    guard html.contains(deviceGrantedTitle) else {
                        throw MASDriverError("device approval was not granted", url: pageURL, html: html)
                    }
                    return
                }
                page = try await submit(
                    [(confirmDeviceField, "on"), (actionField, consentAction)], on: pageURL, html: html,
                    redirectScheme: nil)
            } else {
                throw MASDriverError("unexpected page during device approval", url: pageURL, html: html)
            }
        }
        throw MASDriverError("device approval did not finish", url: verificationURI, html: nil)
    }

    /// Se connecte et autorise, pour quelques minutes, le remplacement de l'identité de
    /// signature croisée sans authentification interactive : ce que fait l'utilisateur sur la page
    /// `approvalUrl` d'une réinitialisation d'identité.
    func allowCrossSigningReset(username: String, password: String) async throws {
        let loginURL = mas.appending(path: "login")
        guard case let .page(pageURL, html) = try await open(loginURL, redirectScheme: nil), pageURL.path == loginPath
        else {
            throw MASDriverError("no login page", url: loginURL, html: nil)
        }
        _ = try await submit(
            [(usernameField, username), (passwordField, password)], on: pageURL, html: html, redirectScheme: nil)

        let viewer = try await graphQL("query { viewer { ... on User { id } } }", variables: [:])
        let userID = try #require(
            ((viewer["viewer"] as? [String: Any])?["id"]) as? String, "MAS has no signed-in user: \(viewer)")
        _ = try await graphQL(
            "mutation($id: ID!) { allowUserCrossSigningReset(input: {userId: $id}) { user { id } } }",
            variables: ["id": userID]
        )
    }

    // MARK: - HTTP

    /// Exécute une requête GraphQL et rend son champ `data` ; des `errors` font échouer.
    private func graphQL(_ query: String, variables: [String: String]) async throws -> [String: Any] {
        let url = mas.appending(path: graphQLPath)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, response) = try await session.data(for: request, delegate: RedirectRefuser.shared)
        let body = String(decoding: data, as: UTF8.self)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["errors"] == nil,
            let result = object["data"] as? [String: Any]
        else {
            throw MASDriverError("GraphQL failed: \(body)", url: url, html: nil)
        }
        return result
    }

    private enum Outcome {
        /// Une page HTML servie avec `200`, et l'URL où elle a été servie (après redirections).
        case page(URL, String)
        /// Une redirection vers le schéma de l'application, non suivie.
        case callback(URL)
    }

    private func open(_ url: URL, redirectScheme: String?) async throws -> Outcome {
        try await send(URLRequest(url: url), redirectScheme: redirectScheme)
    }

    /// Soumet le formulaire de la page — ses champs propres et le jeton CSRF qu'elle porte — à
    /// l'URL de la page.
    private func submit(
        _ fields: [(String, String)], on pageURL: URL, html: String, redirectScheme: String?
    ) async throws -> Outcome {
        guard let csrf = csrfToken(in: html) else {
            throw MASDriverError("no CSRF token on the page", url: pageURL, html: html)
        }
        var request = URLRequest(url: pageURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncoded([(csrfField, csrf)] + fields).utf8)
        return try await send(request, redirectScheme: redirectScheme)
    }

    /// Envoie la requête et suit les redirections HTTP à la main (en `GET`, comme un navigateur
    /// après un `303`), jusqu'à une page ou une redirection vers `redirectScheme`.
    private func send(_ request: URLRequest, redirectScheme: String?) async throws -> Outcome {
        var request = request
        for _ in 0..<10 {
            let (data, response) = try await session.data(for: request, delegate: RedirectRefuser.shared)
            guard let http = response as? HTTPURLResponse, let url = request.url else {
                throw MASDriverError("not an HTTP response", url: request.url ?? mas, html: nil)
            }
            let html = String(decoding: data, as: UTF8.self)
            switch http.statusCode {
            case 200:
                return .page(url, html)
            case 301, 302, 303, 307, 308:
                guard
                    let location = http.value(forHTTPHeaderField: "Location"),
                    let target = URL(string: location, relativeTo: url)?.absoluteURL
                else {
                    throw MASDriverError("redirection without a usable Location", url: url, html: html)
                }
                if let redirectScheme, target.scheme == redirectScheme {
                    return .callback(target)
                }
                guard target.scheme == "http" || target.scheme == "https" else {
                    throw MASDriverError("redirection to an unexpected scheme: \(target)", url: url, html: html)
                }
                request = URLRequest(url: target)
            default:
                throw MASDriverError("HTTP \(http.statusCode)", url: url, html: html)
            }
        }
        throw MASDriverError("too many redirections", url: request.url ?? mas, html: nil)
    }

    private func csrfToken(in html: String) -> String? {
        let pattern = /name="csrf" value="([^"]+)"/
        return html.firstMatch(of: pattern).map { String($0.1) }
    }

    private func formEncoded(_ fields: [(String, String)]) -> String {
        // `urlQueryAllowed` laisse passer `+`, `&` et `=` : trop permissif pour un corps de formulaire.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { name, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(name)=\(encoded)"
        }
        .joined(separator: "&")
    }
}

/// Refuse toute redirection : ``MASDriver`` les suit lui-même, pour ne jamais tenter d'ouvrir le
/// schéma de l'application et pour voir chaque `Location`.
private final class RedirectRefuser: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = RedirectRefuser()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

/// Échec du pilote, avec l'URL et le texte de la page en cause (jamais le mot de passe : il ne
/// figure que dans les corps envoyés, pas dans les pages reçues).
struct MASDriverError: Error, CustomStringConvertible {
    let description: String

    init(_ message: String, url: URL, html: String?) {
        let text =
            html.map {
                $0.replacing(/<[^>]*>/, with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
            } ?? ""
        description = "\(message) at \(url): \(text.prefix(600))"
    }
}
