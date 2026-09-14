# Security policy

## Reporting a vulnerability

**Any vulnerability affecting the Matrix protocol, end-to-end encryption or the Matrix Rust SDK
must be reported to the matrix.org team**, following their responsible disclosure process:
https://matrix.org/security-disclosure-policy/

For a vulnerability specific to MatrixClientKit — the Swift layer in this repository, for instance
token storage or Keychain configuration — open a private security advisory through this
repository's Security tab. Please do not open a public issue.

## Scope

This package implements no cryptographic primitive. Encryption is handled entirely by the Matrix
Rust SDK.
