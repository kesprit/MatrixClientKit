import Testing
import MatrixRustSDK
@testable import MatrixClientKitCore
@testable import MatrixClientKitRust

// Ces deux traducteurs sont de purs `switch` sur des enums amont, avec de l'arithmétique
// d'index. Un décalage d'une unité dans `insert` / `set` / `remove` / `truncate` réordonne
// silencieusement une liste de rooms ou une conversation entière, sans erreur ni plantage :
// exactement le genre de défaut qu'aucun test d'intégration ne rattrape à coup sûr.
//
// LIMITE ASSUMÉE : les arms `append`, `pushFront`, `pushBack`, `insert`, `set` et `reset` non
// vides transportent un `Room` ou un `TimelineItem` amont — des objets FFI opaques, sans
// constructeur utilisable hors d'une session vivante. Les fabriquer via `NoHandle` produirait un
// objet dont le premier appel de méthode plante. Ces arms ne sont donc couverts que sur leur
// forme vide (`append([])`, `reset([])`), et leur arithmétique d'index reste couverte par
// `remove` et `truncate`, qui partagent la même conversion `Int(UInt32)`. La couverture réelle
// du contenu appartient à la suite d'intégration.

// MARK: - TimelineMapper

@Test func timelineClearIsTranslated() {
    #expect(TimelineMapper.diff(from: .clear) == .clear)
}

@Test func timelinePopsAreTranslated() {
    #expect(TimelineMapper.diff(from: .popFront) == .popFront)
    #expect(TimelineMapper.diff(from: .popBack) == .popBack)
}

@Test(arguments: [0, 1, 7, 4_294_967_295] as [UInt32])
func timelineRemoveKeepsItsIndex(index: UInt32) {
    #expect(TimelineMapper.diff(from: .remove(index: index)) == .remove(index: Int(index)))
}

@Test(arguments: [0, 1, 7, 4_294_967_295] as [UInt32])
func timelineTruncateKeepsItsLength(length: UInt32) {
    #expect(TimelineMapper.diff(from: .truncate(length: length)) == .truncate(length: Int(length)))
}

@Test func timelineEmptyBatchesAreTranslatedInPlace() {
    #expect(TimelineMapper.diff(from: .append(values: [])) == .append([]))
    #expect(TimelineMapper.diff(from: .reset(values: [])) == .reset([]))
}

// MARK: - RoomMapper

@Test func roomListClearIsTranslated() async {
    #expect(await RoomMapper.diff(from: .clear) == .clear)
}

@Test func roomListPopsAreTranslated() async {
    #expect(await RoomMapper.diff(from: .popFront) == .popFront)
    #expect(await RoomMapper.diff(from: .popBack) == .popBack)
}

@Test(arguments: [0, 1, 7, 4_294_967_295] as [UInt32])
func roomListRemoveKeepsItsIndex(index: UInt32) async {
    #expect(await RoomMapper.diff(from: .remove(index: index)) == .remove(index: Int(index)))
}

@Test(arguments: [0, 1, 7, 4_294_967_295] as [UInt32])
func roomListTruncateKeepsItsLength(length: UInt32) async {
    #expect(await RoomMapper.diff(from: .truncate(length: length)) == .truncate(length: Int(length)))
}

@Test func roomListEmptyBatchesAreTranslatedInPlace() async {
    #expect(await RoomMapper.diff(from: .append(values: [])) == .append([]))
    #expect(await RoomMapper.diff(from: .reset(values: [])) == .reset([]))
}

// MARK: - Effet réel sur la collection

// Les traducteurs ne sont utiles que composés avec l'applicateur : ce test épingle le couple,
// donc la position exacte que `remove` et `truncate` désignent une fois traduits.
@Test func translatedIndicesDesignateTheSamePositionAsUpstream() {
    let items = ["a", "b", "c", "d"]

    func applied(_ upstream: TimelineDiff) -> [String] {
        switch TimelineMapper.diff(from: upstream) {
        case let .remove(index): return CollectionDiffApplier.apply([.remove(index: index)], to: items)
        case let .truncate(length): return CollectionDiffApplier.apply([.truncate(length: length)], to: items)
        default: return items
        }
    }

    #expect(applied(.remove(index: 0)) == ["b", "c", "d"])
    #expect(applied(.remove(index: 3)) == ["a", "b", "c"])
    #expect(applied(.truncate(length: 2)) == ["a", "b"])
    #expect(applied(.truncate(length: 0)) == [])
}
