# Authentication

Choose a server, find out how it lets users sign in, and sign in with a password, OAuth or a QR
code — then sign in again after the server ended the session.

## Overview

Every sign-in path ends the same way: you get a ``MatrixSession``. Which paths a homeserver accepts
differs: matrix.org and others delegate authentication to Matrix Authentication Service and accept
OAuth only for new accounts, while a plain Synapse still accepts a password. Ask the server first
with ``MatrixClient/loginDetails()``, then offer the matching methods.

This article uses one storage and one OAuth configuration throughout:

```swift
import AuthenticationServices
import CoreImage.CIFilterBuiltins
import MatrixClientKit

let storage = MatrixStorage.appGroup("group.com.example.app")

let configuration = OAuthConfiguration(
    clientName: "Example",
    redirectURI: URL(string: "com.example.app:/callback")!,
    clientURI: URL(string: "https://example.com")!
)
```

``OAuthConfiguration/redirectURI`` must use a scheme of your own: it is the
`callbackURLScheme` you give `ASWebAuthenticationSession`. A scheme in reverse-DNS form of the
host in ``OAuthConfiguration/clientURI`` is the safest choice, as authorization servers may
require it.

## Choose a server

Users type a server name (`matrix.org`), a homeserver URL or their own user ID.
``Matrix/client(server:storage:)`` accepts all three, discovers the homeserver address through the
server's `.well-known` information, and returns a client whose ``MatrixClient/homeserver`` holds
the resolved address:

```swift
do {
    let client = try await Matrix.client(server: "matrix.org", storage: storage)
    print(client.homeserver)
} catch let error as MatrixError {
    // `.network(...)` when the server cannot be reached,
    // `.unexpected` when the input is not a server or its discovery information is unreadable.
}
```

When you already know the exact address, ``Matrix/client(homeserver:storage:)`` skips discovery and
needs no network.

## Find out how to sign in

```swift
let details = try await client.loginDetails()

if details.supportsOAuth {
    // Offer "Continue" (OAuth). Offer "Create account" only if the server says it can.
    let canCreateAccount = details.oauthPrompts.contains(.create)
}
if details.supportsPassword {
    // Offer a username (or email) and password form.
}
```

- ``LoginDetails/supportsOAuth`` also means QR-code login can work: it needs OAuth.
- Offer account creation only when ``LoginDetails/oauthPrompts`` contains ``OAuthPrompt/create``.
  Creating an account with a password is not supported.
- ``LoginDetails/supportsSSO`` is informational: legacy single sign-on is not supported. A server
  that reports only SSO leaves the user with nothing to sign in with here.

## Sign in with a password or an email

```swift
let session = try await client.login(
    .password(username: "alice", password: "…", deviceName: "iPhone")
)

// Or, when the user typed an email address bound to their account:
let sameSession = try await client.login(
    .email(address: "alice@example.com", password: "…", deviceName: "iPhone")
)
```

A refused password throws ``MatrixError/authentication(_:)``. Passwords never appear in a
description or a log line: ``Credentials`` redacts them.

## Sign in with OAuth

``MatrixClient/beginOAuthLogin(_:prompt:loginHint:)`` prepares the sign-in and returns an
``OAuthLoginFlow``. You present the web page, because this package links no UI framework:

```swift
@MainActor
func signInWithOAuth(client: any MatrixClient) async throws -> any MatrixSession {
    let flow = try await client.beginOAuthLogin(configuration, prompt: nil, loginHint: nil)

    do {
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let web = ASWebAuthenticationSession(
                url: flow.authorizationURL,
                callbackURLScheme: configuration.redirectURI.scheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? CancellationError())
                }
            }
            web.presentationContextProvider = myPresentationContextProvider  // your code
            web.start()
        }
        return try await flow.complete(callbackURL: callbackURL)
    } catch {
        // The user closed the web view, or completing failed: abandon the flow.
        await flow.cancel()
        throw error
    }
}
```

When the user closes the web view, `ASWebAuthenticationSession` reports an error: calling
``OAuthLoginFlow/cancel()``, as above, erases what the flow prepared locally.

Pass `prompt: .create` to open the authorization server on its account-creation page — only when
``LoginDetails/oauthPrompts`` contains it — and `loginHint` to prefill the user ID.

Things to know:

- A flow is **single-use**. After ``OAuthLoginFlow/complete(callbackURL:)`` has failed, or after
  ``OAuthLoginFlow/cancel()``, begin a new one. A second `complete` throws
  ``MatrixError/unexpected(message:details:)``.
- ``OAuthLoginFlow/complete(callbackURL:)`` throws `CancellationError` when the user refused on the
  authorization server's page.

## Sign in with a QR code

A device that is already signed in can hand its account to a new device by QR code. Both
directions use one type, ``QRCodeLogin``, driven by its ``QRCodeLogin/state``. The login needs a
homeserver that supports OAuth and QR-code login.

**The signed-in device must hold the account's cross-signing private keys** — it is the device that
created the account's cryptographic identity, or one that recovered it. Otherwise the grant fails
and this device's login ends in `.failed(.unknown)`. A brand-new OAuth account gets its identity at
its first sign-in.

### This device shows the code

```swift
let login = client.loginWithQRCode(configuration)

Task {
    for await state in login.state {
        switch state {
        case .displayQRCode(let bytes):
            qrImage = makeQRImage(from: bytes)
        case .enterCheckCode:
            // The other device shows two digits: ask the user to type them.
            askForCheckCode()
        case .waitingForApproval(let userCode):
            // Tell the user to approve on the other device (some servers show `userCode` there).
            showWaiting(userCode: userCode)
        case .failed(let failure):
            show(failure)
        default:
            break
        }
        if state.isFinished { break }
    }
}

let session = try await login.start()
```

When the user typed the two digits, send them:

```swift
try await login.submitCheckCode(42)
```

Rendering the code needs no dependency beyond Core Image:

```swift
func makeQRImage(from bytes: Data) -> CGImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = bytes
    filter.correctionLevel = "L"
    guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
    else { return nil }
    return CIContext().createCGImage(image, from: image.extent)
}
```

### This device scans the code

The other device shows the QR code; your scanner hands its bytes to the static
``Matrix/loginWithQRCode(scanned:configuration:storage:)``, which needs no client: the code says
which homeserver to use.

```swift
let login = Matrix.loginWithQRCode(scanned: scannedBytes, configuration: configuration, storage: storage)

Task {
    for await state in login.state {
        if case .displayCheckCode(let digits) = state {
            // Show these two digits: the user confirms them on the other device.
            showCheckCode(digits)
        }
        if state.isFinished { break }
    }
}

let session = try await login.start()
```

### Ending and cancelling

- ``QRCodeLoginState/done`` and ``QRCodeLoginState/failed(_:)`` end the flow; ``QRCodeLoginFailure``
  says why. The set of failures is frozen: anything not listed is ``QRCodeLoginFailure/unknown``.
- ``QRCodeLogin/start()`` throws a ``MatrixError`` on failure — the detail is in the state — and
  `CancellationError` after ``QRCodeLogin/cancel()``.
- ``QRCodeLogin/cancel()`` changes the state to `.failed(.cancelled)` at once, but ``QRCodeLogin/start()``
  may return only when the exchange in progress with the other device ends. Once the session is
  being built, `cancel()` has no effect and `start()` returns the session.
- The session a QR login returns starts out verified.

## After a soft logout

A server can end a session without revoking the device's keys: the session then reports
``AuthState/softLoggedOut``, syncing stops, and nothing local is erased. Watch for it:

```swift
Task {
    for await state in session.authState {
        switch state {
        case .signedIn: break
        case .softLoggedOut: showSignInAgainScreen()
        case .signedOut: showSignedOutScreen()
        }
    }
}
```

Sign in again **on the same device**, so the encryption keys are kept and earlier encrypted
messages stay readable:

```swift
let newSession = try await session.reauthenticate(
    .password(username: "alice", password: "…", deviceName: nil)
)
```

For an account that uses OAuth, ``MatrixSession/beginOAuthReauthentication(_:)`` returns an
``OAuthLoginFlow`` that you present exactly like a first sign-in; its
``OAuthLoginFlow/complete(callbackURL:)`` returns the new session.

- Both return a **new** session. The old one reports ``AuthState/signedOut``: drop your references
  to it and rebuild whatever you hung on it — the rooms, the timelines, your sync loop.
  Its data now belongs to the new session.
- If signing in fails (wrong password, no network, a closed web view), the old session stays
  ``AuthState/softLoggedOut``, syncing still stopped, and the user can try again. A different
  account's credentials fail with `.authentication(.invalidCredentials)`.
- Called outside ``AuthState/softLoggedOut``, or while another reauthentication is running, both
  throw ``MatrixError/unexpected(message:details:)`` and touch nothing.

Test these flows without a server: see <doc:TestingWithMocks>.
