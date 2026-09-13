import Testing
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

// La construction du contenu ne peut pas être vérifiée plus finement à ce niveau :
// `RoomMessageEventContentWithoutRelation` est un objet FFI opaque, sans accesseur au corps
// du message. Le mappage réel est couvert par la suite d'intégration (Task 16), qui envoie
// un message et vérifie son écho local dans la timeline.
//
// Le cas `.markdown` n'a pas de test équivalent : `messageEventContentFromMarkdown(md:)` n'est
// pas une fonction qui peut lever d'erreur en amont, donc `eventContent(for: .markdown)` ne peut
// échouer pour aucune entrée — un test dessus ne vérifierait rien de plus que la compilation.
@Test func plainTextEventContentIsBuiltWithoutThrowing() throws {
    _ = try TimelineMapper.eventContent(for: .text("bonjour"))
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
