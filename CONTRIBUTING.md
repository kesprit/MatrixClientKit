# Contributing

## Before opening a pull request

    swift build
    swift test --skip MatrixClientKitIntegrationTests

The integration tests do not run by default: see
`Tests/MatrixClientKitIntegrationTests/README.md`.

## Architecture rules

- `MatrixClientKitCore` must **never** import `MatrixRustSDK`. That is what guarantees no upstream
  type leaks into the public API.
- No Rust SDK type may appear in a `public` signature.
- No `@MainActor` in `Core` or in `Rust`.
- Diff streams use `.unbounded`; snapshot streams use `.bufferingNewest(1)`.

## Adding a case to `MatrixError`

Top-level cases are frozen for the lifetime of a major version. A newly distinguishable error must
be reported through `.unexpected` until the next major: adding a case would break the build of
every application depending on the package.

## Bumping the Rust SDK

1. Update the pinned version in `Package.swift`.
2. Run the integration suite against a real homeserver (see
   `Tests/MatrixClientKitIntegrationTests/README.md`).
3. Update the README compatibility table and the CHANGELOG.
