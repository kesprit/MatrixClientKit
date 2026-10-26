/// Retient le `Client` FFI de la session pour chaque objet Swift qui garde un objet FFI dépendant
/// de lui (`RoomListService`, `Room`, `Timeline`, `SyncService`, `Encryption`…), et libère ces
/// objets pendant que le client vit encore.
///
/// Même raison que `RustMatrixSession.Dependents` : le dernier `Arc<ClientInner>` doit tomber dans
/// le runtime Tokio, ce que seul le `Drop` du `Client` FFI garantit. Une timeline, un handle de
/// room ou un service gardés par l'application après la libération de la session deviendraient
/// sinon le dernier détenteur du client interne — panique « there is no reactor running », arrêt
/// du processus. Chaque porteur retient une instance (partagée par toute la session) et appelle
/// ``release(_:)`` dans son `deinit` : le client reste en vie au moins jusqu'à ce point, quel que
/// soit l'ordre dans lequel l'application lâche ses références.
///
/// Générique sur l'objet retenu (`AnyObject & Sendable`) pour être testable sans le SDK ; en
/// production, c'est le `Client` FFI.
final class ClientLifetime: Sendable {
    private let client: any AnyObject & Sendable

    init(client: any AnyObject & Sendable) {
        self.client = client
    }

    /// Libère `dependent` pendant que le client est garanti vivant.
    func release<T>(_ dependent: inout T?) {
        withExtendedLifetime(client) {
            dependent = nil
        }
    }
}
