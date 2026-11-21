/// A page of the account management offered by the authorization server.
///
/// A struct, not an enum: new pages can be added without breaking your `switch`.
public struct AccountManagementAction: Sendable, Hashable {
    /// The page, with the identifier it targets when it has one. Package-visible so the Rust
    /// layer can map it to the upstream action.
    package enum Kind: Sendable, Hashable {
        case overview
        case profile
        case devices
        case device(DeviceID)
        case deleteDevice(DeviceID)
        case deactivateAccount
    }

    package let kind: Kind

    private init(_ kind: Kind) {
        self.kind = kind
    }

    /// The account management home page.
    public static let overview = AccountManagementAction(.overview)
    /// The page to edit the user's profile.
    public static let profile = AccountManagementAction(.profile)
    /// The list of the user's devices.
    public static let devices = AccountManagementAction(.devices)
    /// The details of one device.
    public static func device(_ id: DeviceID) -> AccountManagementAction {
        AccountManagementAction(.device(id))
    }
    /// The page to sign one device out.
    public static func deleteDevice(_ id: DeviceID) -> AccountManagementAction {
        AccountManagementAction(.deleteDevice(id))
    }
    /// The page to deactivate the account.
    public static let deactivateAccount = AccountManagementAction(.deactivateAccount)
}
