import Testing
import MatrixClientKitCore

@Test func recoveryKeyNeverAppearsInItsDescriptions() {
    let key = RecoveryKey(rawValue: "EsTc 1234 abcd")

    // Une clé interpolée dans un log ne doit jamais s'y retrouver en clair.
    #expect(!"\(key)".contains("EsTc"))
    #expect(!String(reflecting: key).contains("EsTc"))
    #expect(key.rawValue == "EsTc 1234 abcd")
}

@Test func recoveryKeysCompareByValue() {
    #expect(RecoveryKey(rawValue: "a") == RecoveryKey(rawValue: "a"))
    #expect(RecoveryKey(rawValue: "a") != RecoveryKey(rawValue: "b"))
}
