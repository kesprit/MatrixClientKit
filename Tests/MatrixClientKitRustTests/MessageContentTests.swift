import Testing
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

// `RoomMessageEventContentWithoutRelation` est un objet opaque du binding généré : il n'expose
// que `withMentions(mentions:)`, aucune propriété inspectable (pas de `.body`). On ne peut donc
// tester ici que l'absence d'erreur pour une entrée typique ; la couverture du contenu produit
// relève de la suite d'intégration manuelle de la Task 16.
@Test func plainTextProducesEventContentWithoutThrowing() throws {
    _ = try TimelineMapper.eventContent(for: .text("bonjour"))
}

@Test func markdownProducesEventContentWithoutThrowing() throws {
    _ = try TimelineMapper.eventContent(for: .markdown("**gras**"))
}

@Test func sendStateIsMappedFromUpstream() {
    #expect(TimelineMapper.sendState(from: nil) == .sent)
    #expect(TimelineMapper.sendState(from: .notSentYet(progress: nil)) == .sending)
    #expect(TimelineMapper.sendState(from: .sent(eventId: "$abc")) == .sent)

    let failed = TimelineMapper.sendState(from: .sendingFailed(
        error: .crossVerificationRequired,
        isRecoverable: true
    ))
    #expect(failed.isFailed)
}
