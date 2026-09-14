# Integration tests

These tests do not run in continuous integration. They exercise the whole chain against a real
homeserver and must be run **manually before every bump of the Rust SDK**.

## Running them

    MATRIX_TEST_HOMESERVER=https://your-homeserver \
    MATRIX_TEST_USERNAME=username \
    MATRIX_TEST_PASSWORD=secret \
    MATRIX_TEST_ROOM_ID='!room:your-homeserver' \
    swift test --filter MatrixClientKitIntegrationTests

Without those variables the suite is skipped, which is the expected behaviour in CI.

## Requirements on the test account

Use an account **dedicated** to testing, for two reasons:

- The account must belong to **at least one joined room**: `loginSyncAndListRooms` checks that a
  snapshot of the joined-room list is non-empty, not merely that it is consistent.
- These tests send real messages to `MATRIX_TEST_ROOM_ID` and open a real session in every case.
  Each test signs the session out at the end — but if a case is interrupted or exceeds its one
  minute (`.timeLimit`), the device may stay registered server-side: cleanup runs in a detached
  task to maximise its chances of reaching the server even after cancellation, but nothing
  guarantees the homeserver processed it before the process exits. So don't reuse this account for
  anything else, and prune its devices from time to time if you run the suite often.
