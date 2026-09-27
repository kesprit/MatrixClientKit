# Integration tests

These tests do not run in continuous integration. They exercise the whole chain against a real
homeserver and must be run **manually before every bump of the Rust SDK**.

## Running them

    MATRIX_TEST_HOMESERVER=https://your-homeserver \
    MATRIX_TEST_USERNAME=username \
    MATRIX_TEST_PASSWORD=secret \
    MATRIX_TEST_ROOM_ID='!room:your-homeserver' \
    MATRIX_TEST_RECOVERY_KEY='EsTc …' \
    MATRIX_TEST_SENDER_USERNAME=sender \
    MATRIX_TEST_SENDER_PASSWORD=secret \
    swift test --filter MatrixClientKitIntegrationTests

Without the first three variables the suite is skipped, which is the expected behaviour in CI.

`MATRIX_TEST_ROOM_ID` is a room **ID**, which starts with `!` — not an alias, which starts with
`#`. Element X does not show it; ask the homeserver to resolve the alias instead:

    curl -s 'https://your-homeserver/_matrix/client/v3/directory/room/%23your-alias%3Ayour-homeserver'

## Checking the account before running

Most failures of this suite come from the account, not from the code: a refused password, a room
the account has not joined, recovery not set up. Check all three in one go — it changes nothing on
the account and signs its own session out:

    ./Scripts/check-integration-env.sh

Optional variables:

- `MATRIX_TEST_RECOVERY_KEY` enables the verification and recovery cases. Set up recovery **once**
  on the test account — for instance by signing in with Element — and keep its key. The tests never
  change it, so it stays valid from one run to the next. Recovery must actually be set up on the
  account: without it the homeserver answers "The info about the secret key could not have been
  found in the account data of the user", and the recovery cases fail for that reason rather than
  for anything the package does.
- `MATRIX_TEST_FRESH_USERNAME` and `MATRIX_TEST_FRESH_PASSWORD` name an account that has **never
  signed in anywhere**. They enable the case checking that signing in creates a cross-signing
  identity. It is meaningful only on the account's first run: register a new account each time you
  want to check it.
- `MATRIX_TEST_SENDER_USERNAME` and `MATRIX_TEST_SENDER_PASSWORD` name a **second** account,
  also a member of `MATRIX_TEST_ROOM_ID`. It sends the message the main account's notification
  service extension must resolve. Without them, the push case that needs two accounts is skipped.
  The room must not be muted for the main account, or the event is filtered out.

## Requirements on the test account

Every case runs one after the other, across all three suites — not just within one — because they
share a single test account and a single Keychain entry per process; do not remove the
serialization to speed the suite up.

Use an account **dedicated** to testing, for two reasons:

- The account must belong to **at least one joined room**: `loginSyncAndListRooms` checks that a
  snapshot of the joined-room list is non-empty, not merely that it is consistent.
- These tests send real messages to `MATRIX_TEST_ROOM_ID` and open a real session in every case.
  Each test signs the session out at the end — but if a case is interrupted or exceeds its one
  minute (`.timeLimit`), the device may stay registered server-side: cleanup runs in a detached
  task to maximise its chances of reaching the server even after cancellation, but nothing
  guarantees the homeserver processed it before the process exits. So don't reuse this account for
  anything else, and prune its devices from time to time if you run the suite often.
- `aServerSideLogoutSignsTheSessionOutAndErasesItsStore` signs **every** session of the account out,
  as "sign out of all devices" would. Anything else signed in to that account is signed out too.
- The Keychain holds one persisted session per service, so the verification case — which signs the
  same account in twice in one process — overwrites the first session's entry with the second's.
  The case never restores a session, so this does not affect it.
- The notification cases use an App Group storage. On macOS, outside a sandbox, `FileManager`
  creates its container under `~/Library/Group Containers/group.com.matrixclientkit.integration.*`;
  each case removes its own. An interrupted run may leave one behind: delete them by hand.
- In the two-account case, the sender signs in **before** the main account and signs out **after**
  the extension opened: the Keychain holds one session entry per process, which every sign-in
  overwrites and every sign-out erases.
