import MatrixRustSDK

/// Sous-ensemble de `Client` dont le service de compte a besoin.
///
/// Couture de testabilité : `Client` est une classe FFI qu'un test ne peut pas construire.
/// ``ClientAccountDriver`` l'adapte ; seul le type de retour de l'abonnement diffère.
protocol AccountDriving: Sendable {
    func accountUrl(action: MatrixRustSDK.AccountManagementAction?) async throws -> String?
    func ignoredUsers() async throws -> [String]
    func ignoreUser(userId: String) async throws
    func unignoreUser(userId: String) async throws
    func deactivateAccount(authData: AuthData?, eraseData: Bool) async throws
    func subscribeToIgnoredUsers(listener: any IgnoredUsersListener) -> any TaskHandleProtocol
}

/// Adapte le `Client` FFI à ``AccountDriving``. Libéré à travers ``ClientLifetime``.
struct ClientAccountDriver: AccountDriving {
    let client: Client

    func accountUrl(action: MatrixRustSDK.AccountManagementAction?) async throws -> String? {
        try await client.accountUrl(action: action)
    }

    func ignoredUsers() async throws -> [String] {
        try await client.ignoredUsers()
    }

    func ignoreUser(userId: String) async throws {
        try await client.ignoreUser(userId: userId)
    }

    func unignoreUser(userId: String) async throws {
        try await client.unignoreUser(userId: userId)
    }

    func deactivateAccount(authData: AuthData?, eraseData: Bool) async throws {
        try await client.deactivateAccount(authData: authData, eraseData: eraseData)
    }

    func subscribeToIgnoredUsers(listener: any IgnoredUsersListener) -> any TaskHandleProtocol {
        client.subscribeToIgnoredUsers(listener: listener)
    }
}
