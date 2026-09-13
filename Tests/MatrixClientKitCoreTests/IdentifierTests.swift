import Testing
@testable import MatrixClientKitCore

@Test func userIDAcceptsWellFormedValue() throws {
    let id = try #require(UserID(rawValue: "@alice:matrix.org"))
    #expect(id.localpart == "alice")
    #expect(id.serverName == "matrix.org")
    #expect(id.description == "@alice:matrix.org")
}

@Test(arguments: ["alice:matrix.org", "@alice", "@:matrix.org", "@alice:", ""])
func userIDRejectsMalformedValues(raw: String) {
    #expect(UserID(rawValue: raw) == nil)
}

@Test func userIDKeepsPortInServerName() throws {
    let id = try #require(UserID(rawValue: "@bob:example.com:8448"))
    #expect(id.serverName == "example.com:8448")
}

@Test func roomIDAcceptsLegacyAndModernForms() {
    #expect(RoomID(rawValue: "!abc:matrix.org") != nil)
    #expect(RoomID(rawValue: "!opaqueIdentifier") != nil)
}

@Test(arguments: ["abc:matrix.org", "!", ""])
func roomIDRejectsMalformedValues(raw: String) {
    #expect(RoomID(rawValue: raw) == nil)
}

@Test func eventIDRequiresDollarPrefix() {
    #expect(EventID(rawValue: "$abcdef") != nil)
    #expect(EventID(rawValue: "abcdef") == nil)
    #expect(EventID(rawValue: "$") == nil)
}

@Test func deviceIDRejectsEmptyValue() {
    #expect(DeviceID(rawValue: "ABCDEF") != nil)
    #expect(DeviceID(rawValue: "") == nil)
}

@Test func identifiersAreHashableByRawValue() throws {
    let a = try #require(UserID(rawValue: "@alice:matrix.org"))
    let b = try #require(UserID(rawValue: "@alice:matrix.org"))
    #expect(a == b)
    #expect(Set([a, b]).count == 1)
}
