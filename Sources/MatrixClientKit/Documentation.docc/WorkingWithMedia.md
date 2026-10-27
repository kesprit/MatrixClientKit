# Media

Show the images, videos, audio and files of a room, send your own with a progress bar, and cancel,
retry or give up on a send that failed.

## Overview

A media message is a ``Message`` whose ``Message/media`` is not `nil`. Reading its bytes goes
through ``MatrixSession/media``, a ``MediaService``; sending one goes through the room's
``Timeline``. Both sides use the same few types:

- ``MediaSource`` says where a media lives on the homeserver. It is opaque: you never build the
  request yourself, you hand the source back to the ``MediaService``. It is `Codable`, so it makes a
  good key for your own cache — but the encoding of an encrypted source contains its decryption
  keys: store it as sensitive data, as you would the media itself. Its descriptions and `dump` show
  only the URL and whether it is encrypted, so logging a source does not leak them.
- ``MediaAttachment`` describes a received media: its ``MediaAttachment/kind``, file name, caption,
  MIME type, size, dimensions, duration, thumbnail and blurhash.
- ``Attachment`` describes a media you send.

The examples below assume a `session`, a `timeline` and an `item` obtained as in
<doc:GettingStarted>.

## Show a received image

The package does not cache anything, and does not decode images: it gives you bytes. A typical
display is a placeholder first, then the homeserver's thumbnail, then — only if the user opens the
image — the full content.

```swift
import MatrixClientKit

// The light version, for a list: the sender's thumbnail if there is one, the homeserver's if not.
func thumbnailData(of media: MediaAttachment, session: any MatrixSession) async throws -> Data {
    if let thumbnail = media.thumbnail {
        return try await session.media.content(of: thumbnail)
    }
    return try await session.media.thumbnail(of: media.source, width: 320, height: 240)
}

// The original, decrypted when the room is encrypted — when the user opens the image.
func fullData(of media: MediaAttachment, session: any MatrixSession) async throws -> Data {
    try await session.media.content(of: media.source)
}
```

While the thumbnail loads, draw a placeholder from ``MediaAttachment/blurhash`` with the decoder of
your choice, when it is set.

Two ways to get a smaller image, which differ in who produces it:

- ``MediaAttachment/thumbnail`` is a thumbnail **the sender** attached to the message. It is
  optional, and read with ``MediaService/content(of:)`` like any other media.
- ``MediaService/thumbnail(of:width:height:)`` asks **the homeserver** for a thumbnail of at least
  that size.

Finally, ``MediaService/content(of:)`` returns the whole media. Check ``MediaAttachment/size``
before loading a video into memory: for a large file, ``MediaService/file(of:filename:mimeType:)``
writes it to disk instead.

A room's avatar is a media too: ``RoomSummary/avatar`` is a ``MediaSource`` you pass to the same
methods.

```swift
func avatarData(of room: RoomSummary, session: any MatrixSession) async throws -> Data? {
    guard let avatar = room.avatar else { return nil }
    return try await session.media.thumbnail(of: avatar, width: 96, height: 96)
}
```

## Keep a file

``MediaService/file(of:filename:mimeType:)`` downloads a media into a temporary file and returns a
``MediaFile``. The file is deleted when you release the value. To keep it, move it with
``MediaFile/persist(to:)`` before:

```swift
func save(_ media: MediaAttachment, to destination: URL, session: any MatrixSession) async throws {
    let file = try await session.media.file(
        of: media.source,
        filename: media.filename,
        mimeType: media.mimeType ?? "application/octet-stream"
    )
    // `file.url` is readable here, for a preview for instance.
    guard try file.persist(to: destination) else {
        // The file could not be kept; the temporary one is still deleted on release.
        return
    }
    // From here on, the file is at `destination`: `file.url` no longer points to it.
}
```

## Send a media

Describe the media with an ``Attachment`` and give it to the timeline. Its source is a local file
that must stay in place until the upload ends, or bytes in memory with the file name the recipients
see.

```swift
func sendPhoto(at url: URL, timeline: any Timeline) async throws {
    let attachment = Attachment(
        source: .file(url),
        kind: .image(dimensions: MediaDimensions(width: 1600, height: 1200), blurhash: nil),
        mimeType: "image/jpeg",
        caption: "Sunset"
    )
    let upload = try await timeline.send(attachment)
    try await upload.waitUntilQueued()
}
```

Everything the recipients use to preview the media — a thumbnail, its dimensions, a blurhash, a
voice message's waveform and duration — is **produced by your application** and given in the
``Attachment``: the package neither decodes nor encodes media. Without a thumbnail, recipients get
the media alone. Only images and videos carry one: ``Attachment/thumbnail`` is ignored for audio,
voice messages and files.

Before building a large attachment, ``MediaService/maxUploadSize()`` tells you the largest upload
the homeserver accepts.

``Timeline/send(_:)-(Attachment)`` throws ``MatrixError/notFound(_:)`` with `.media`, before any
upstream call, when a local file — the media, or the thumbnail of an image or a video — does not
exist.

### Show the progress

The local echo of your media appears in ``Timeline/items`` right away. While it uploads,
``Message/uploadProgress`` is not `nil`:

```swift
func progressFraction(of item: TimelineItem) -> Double? {
    guard case let .message(message) = item.kind else { return nil }
    return message.uploadProgress?.fractionCompleted
}
```

``UploadProgress/fractionCompleted`` is between 0 and 1. The progress is `nil` as soon as the upload
ends, whatever its outcome: from then on, follow ``Message/sendState``.

## Cancel, retry or give up

The ``AttachmentUpload`` that ``Timeline/send(_:)-(Attachment)`` returns controls the media only
**until it is queued**:

- ``AttachmentUpload/cancel()`` stops the preparation; the local echo never appears, or is removed.
- ``AttachmentUpload/waitUntilQueued()`` returns once the media is in the send queue and its local
  echo is in ``Timeline/items``. That is not delivery: follow the echo's ``Message/sendState`` for
  that. You may call it several times, from several tasks: every call reports the same outcome.

Releasing the ``AttachmentUpload`` cancels nothing, and neither does cancelling the Swift task that
awaits ``AttachmentUpload/waitUntilQueued()``: the upload goes on. Only
``AttachmentUpload/cancel()`` stops it.

Once queued, the media is a local echo like any message, and is controlled the same way, through
a ``SendHandle`` obtained from the echo with ``Timeline/sendHandle(for:)``. This is the path of the
"retry" and "give up" buttons — for text as well, and even after the application was relaunched:

```swift
func retryOrDiscard(_ item: TimelineItem, timeline: any Timeline) async throws {
    guard case let .message(message) = item.kind,
          let handle = timeline.sendHandle(for: item)
    else { return }

    switch message.sendState {
    case .failed(_, isRecoverable: true):
        // Connectivity or a transient fault: sending again as is can work.
        try await handle.retry()
    case .failed(_, isRecoverable: false):
        // The user must fix something first, or give up.
        try await handle.cancel()
    case .sending:
        // Cancels the send if the message has not left yet. `false`: it had already been sent.
        let cancelled = try await handle.cancel()
        _ = cancelled
    case .sent:
        break
    }
}
```

``Timeline/send(_:)-(MessageContent)`` returns a ``SendHandle`` too, which you may keep or ignore.

``Timeline/sendHandle(for:)`` returns `nil` for an item that is remote or already sent. It only
knows the items that a subscription to ``Timeline/items`` has seen, which is always the case of an
item you display.

## What to remember

- Thumbnails, blurhashes, waveforms and durations of the media you send are your application's job.
- ``AttachmentUpload/cancel()`` only stops the preparation; to cancel or retry a queued media, use
  ``Timeline/sendHandle(for:)`` on its local echo.
- ``AttachmentUpload/waitUntilQueued()`` is not delivery.
- Upload progress relies on the upstream SDK's progress reporting, which the package turns on for
  you. Send handles do not depend on it.
- The encoding of an encrypted ``MediaSource`` carries its keys: store it as sensitive data.

To test code that shows or sends media without a homeserver, see <doc:TestingWithMocks>.
