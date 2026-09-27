import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private let appGroup = MatrixStorage.appGroup("group.com.example.app")
private let local = MatrixStorage.local(directory: FileManager.default.temporaryDirectory)

@Test func anAppGroupApplicationTakesTheLockAsTheApp() throws {
    #expect(try CrossProcessLock.configuration(for: appGroup, role: .application) == .multiProcess(holderName: "app"))
}

@Test func anAppGroupExtensionTakesTheLockAsTheExtension() throws {
    #expect(
        try CrossProcessLock.configuration(for: appGroup, role: .notificationExtension)
            == .multiProcess(holderName: "nse")
    )
}

@Test func aLocalApplicationRunsInASingleProcess() throws {
    #expect(try CrossProcessLock.configuration(for: local, role: .application) == .singleProcess)
}

@Test func anExtensionCannotOpenALocalStorage() {
    #expect(throws: MatrixError.storage(.unavailable)) {
        try CrossProcessLock.configuration(for: local, role: .notificationExtension)
    }
}

@Test func theRestorerAppliesItsRoleByDefault() throws {
    let restorer = SessionRestorer(storage: appGroup, secureStore: InMemorySecureStore(), role: .notificationExtension)

    #expect(try restorer.lockConfiguration() == .multiProcess(holderName: "nse"))
}

@Test func theRestorerDefaultsToTheApplicationRole() throws {
    let restorer = SessionRestorer(storage: appGroup, secureStore: InMemorySecureStore())

    #expect(restorer.role == .application)
    #expect(try restorer.lockConfiguration() == .multiProcess(holderName: "app"))
}

@Test func anUnsetPolicyLeavesTheBuilderAsIn02() throws {
    let restorer = SessionRestorer(storage: appGroup, secureStore: InMemorySecureStore(), lockPolicy: .unset)

    #expect(try restorer.lockConfiguration() == nil)
}
