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

    let failed = TimelineMapper.sendState(
        from: .sendingFailed(
            error: .crossVerificationRequired,
            isRecoverable: true
        ))
    #expect(failed.isFailed)

    // `reason` finit dans une interface : il doit être lisible, pas un nom de cas Swift amont.
    guard case let .failed(reason, isRecoverable) = failed else { return }
    #expect(!reason.contains("crossVerificationRequired"))
    #expect(reason.contains("verified"))
    // Relayé depuis l'amont, pas reconstruit : c'est la seule information sur laquelle une
    // interface décide d'offrir « réessayer ».
    #expect(isRecoverable)
}

/// Le drapeau doit être relayé dans les deux sens : le figer à `true` ferait offrir « réessayer »
/// sur un envoi garé jusqu'à intervention de l'utilisateur, et le figer à `false` priverait de
/// réessai un envoi qui repartirait tout seul.
@Test(arguments: [true, false])
func recoverabilityIsRelayedFromUpstream(isRecoverable: Bool) {
    let state = TimelineMapper.sendState(
        from: .sendingFailed(error: .missingMediaContent, isRecoverable: isRecoverable))

    let expected = SendState.failed(
        reason: "The media to send is missing from the cache.",
        isRecoverable: isRecoverable
    )
    #expect(state == expected)
    #expect(state.isRecoverableFailure == isRecoverable)
}
