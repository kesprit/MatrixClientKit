# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versioning
follows [SemVer](https://semver.org/).

## [0.1.1] - 2026-09-13

### Fixed

- Sessions refreshed by the SDK are now persisted. Automatic token refresh is on by default:
  without a session delegate a refreshed token lived only in memory, the stored session went stale
  in silence, and the user was signed out on the next launch without a single error being reported.
- The delegate refuses to hand back a session belonging to a user other than the one requested.

### Changed

- `SessionPersistence` is now a synchronous type. The underlying storage is already concurrency-safe,
  and the SDK calls its session delegate synchronously. No public API is affected.

## [0.1.0] - 2026-09-13

### Added

- Password authentication and restoration of a persisted session.
- App Group and Keychain storage, configured for extensions.
- Sync control and a sync-state stream.
- Observable room list, delivered as snapshots.
- Observable timeline, backward pagination and sending text messages.
- `MatrixError`, typed errors with `isRetryable` and `retryAfter`.
- The `MatrixClientKitMocks` product, for applications' own tests.
- Bundled Matrix Rust SDK: 26.09.07.

### Verified

- Full path exercised against a real homeserver (Tuwunel 1.8.1): login, sync, room list, sending a
  message and its local echo.
