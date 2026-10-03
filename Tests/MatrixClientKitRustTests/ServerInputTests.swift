import Testing
@testable import MatrixClientKitRust
import MatrixClientKitCore

@Test func surroundingWhitespaceIsTrimmed() throws {
    #expect(try ServerInput.normalize("  matrix.org \n") == "matrix.org")
}

@Test func aUserIDIsReducedToItsServerName() throws {
    #expect(try ServerInput.normalize("@alice:matrix.org") == "matrix.org")
    #expect(try ServerInput.normalize("@alice:example.com:8448") == "example.com:8448")
}

@Test func anURLIsKeptAsIs() throws {
    #expect(try ServerInput.normalize("https://matrix.example.com/") == "https://matrix.example.com/")
}

@Test(arguments: ["", "   ", "@alice", "@alice:"])
func unusableInputIsRejectedBeforeAnyNetworkCall(_ input: String) {
    #expect(throws: MatrixError.self) { try ServerInput.normalize(input) }
}
