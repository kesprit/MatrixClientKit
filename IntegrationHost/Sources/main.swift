// Hôte signé des tests d'intégration : une application vide, dont l'unique rôle est de porter
// l'entitlement `keychain-access-groups` que le bundle de tests hérite en s'y chargeant.
import AppKit

let application = NSApplication.shared
application.run()
