# Verification and recovery

Verify a new device, set up recovery, and restore a user's encrypted history.

## Overview

End-to-end encryption is always on. What an application drives is **trust**: whether this device is
verified — which lets it read history and be trusted by others — and whether the user's keys are
recoverable if every device is lost.

Everything goes through ``MatrixSession/encryption``, an ``EncryptionService``. Its three state
streams start with the current value, so a screen opened at any time shows the right thing.

## Decide what to offer

Right after sign-in, read the state and pick one path:

| Condition | Offer |
| --- | --- |
| ``VerificationStatus/unverified`` and ``EncryptionService/hasDevicesToVerifyAgainst()`` | "Verify with another device" first, "Use your recovery key" second |
| ``RecoveryState/incomplete`` | "Enter your recovery key" |
| ``RecoveryState/disabled`` and not ``EncryptionService/backupExistsOnServer()`` | "Set up recovery" |
| Right after the first sign-in, ``EncryptionService/isLastDevice()`` and ``RecoveryState/disabled`` | "Set up recovery" — without it, losing this device can leave the account unverifiable (see below) |
| Signing out, ``EncryptionService/isLastDevice()`` and recovery disabled | Warn that encrypted history will be lost |

```swift
let encryption = session.encryption

for await status in encryption.verificationStatus where status != .unknown {
    if status == .unverified, try await encryption.hasDevicesToVerifyAgainst() {
        showVerifyWithAnotherDevice()
    }
    break
}
```

``VerificationStatus/unknown`` lasts until the first sync has loaded the user's identity: wait for
another value before deciding.

## Verify with another device

``EncryptionService/sessionVerification`` publishes the flow as a state machine. Observe
``SessionVerification/state`` and call the command the current state allows:

```swift
func observe(_ verification: any SessionVerification, isRequester: Bool) -> Task<Void, Never> {
    Task {
        for await state in verification.state {
            do {
                switch state {
                case .incomingRequest(let request):
                    showIncomingRequest(from: request.deviceDisplayName ?? request.deviceID.rawValue)
                case .ready:
                    // Only the device that asked for verification starts the comparison.
                    if isRequester { try await verification.startSAS() } else { showProgress() }
                case .comparing(.emojis(let emojis)):
                    showEmojis(emojis)            // then approve() or decline()
                case .comparing(.decimals(let numbers)):
                    showNumbers(numbers)
                case .verified:
                    showSuccess()
                case .cancelled, .failed:
                    showFailure()
                case .idle, .waitingForOtherDevice, .startingSAS, .confirming:
                    showProgress()
                }
            } catch {
                // A command that throws must not end the observation: keep observing.
            }
        }
    }
}

// On the device that asks another of the user's devices to verify it:
let verification = session.encryption.sessionVerification
let observation = observe(verification, isRequester: true)
try await verification.requestVerification()

// On the device that receives the request, observe with `isRequester: false`
// and call accept() or cancel() from the incoming request screen — cancel()
// is what refuses a request; decline() only rejects emojis that don't match.
```

A command called in a state that does not allow it throws ``MatrixError/unexpected(message:details:)``
without doing anything. Only one verification runs at a time: a request that arrives during a flow
is ignored. A command driven by a state that is already stale — the other device moved the flow on
in the meantime — may throw ``MatrixError/unexpected(message:details:)`` too: this is harmless, keep
observing.

``SASEmoji/description`` is the English name from the Matrix specification. To localise it, use
``SASEmoji/index`` against the specification's SAS emoji table.

## Set up recovery

```swift
let key = try await session.encryption.enableRecovery { progress in
    if case .backingUp(let uploaded, let total) = progress {
        print("Backed up \(uploaded) of \(total) keys")
    }
}
showRecoveryKey(key.rawValue)   // the only time the key is available
```

``RecoveryKey`` redacts its description: interpolating it in a log never leaks it. Show
``RecoveryKey/rawValue`` to the user, once, and ask them to store it.

``EncryptionService/resetRecoveryKey()`` replaces the key — the previous one stops working —
and ``EncryptionService/disableRecovery()`` deletes the backup from the server.

## Restore with the recovery key

```swift
do {
    try await session.encryption.recover(with: typedKey)
} catch MatrixError.encryption(.invalidRecoveryKey) {
    showWrongKey()
}
```

A successful recovery verifies this device: ``EncryptionService/verificationStatus`` moves to
``VerificationStatus/verified``.

## Signed out by the server

When the user removes this device from another one, the homeserver ends the session.
``MatrixSession/authState`` reports it:

```swift
for await state in session.authState {
    switch state {
    case .signedIn: continue
    case .softLoggedOut:
        try? await session.logout()   // nothing was erased yet: erases it, then reports .signedOut
    case .signedOut:
        showSignIn()                  // local data is already erased
    }
}
```

## What is not covered yet

Verifying other users, QR-code verification — which the bundled SDK does not expose — and resetting
a lost cryptographic identity are not part of this version.

Without an identity reset, recovery is the only safety net. For an account that has no cross-signing
identity, one is created automatically; its private keys live only on this device until recovery is
set up. If the user never sets up recovery and then loses or signs out of their last device, the
next sign-in finds an identity whose keys are gone and no device to verify against: that account
stays unverified in this version. Offer to set up recovery right after the first sign-in.
