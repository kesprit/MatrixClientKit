import MatrixRustSDK

/// Vérifie à la compilation que la dépendance amont est correctement résolue et liée.
/// Supprimé en Task 6, quand le pont réel occupe ce fichier.
enum UpstreamLinkCheck {
    static func canReferenceUpstreamTypes() -> Bool {
        String(describing: ClientBuilder.self).isEmpty == false
    }
}
