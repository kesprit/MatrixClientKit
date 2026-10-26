import Testing
import Foundation
import CoreGraphics
import ImageIO
import Synchronization
import UniformTypeIdentifiers
import MatrixClientKit

extension HarnessTests {
    // Médias, handles d'envoi et durée de vie des objets FFI contre `synapse-password` (spec 0.5,
    // §5 et §7.2). Chaque cas crée son salon par l'API brute, supprime son répertoire et déconnecte
    // sa session, même interrompu (`withMediaSession`).
    @Suite
    struct MediaHarnessTests {
        @Test(.timeLimit(.minutes(2)))
        func imageRoundTripsInPlainRoom() async throws {
            try await imageRoundTrip(encrypted: false)
        }

        @Test(.timeLimit(.minutes(2)))
        func imageRoundTripsInEncryptedRoom() async throws {
            try await imageRoundTrip(encrypted: true)
        }

        /// Une image envoyée depuis un fichier, avec vignette : l'écho local apparaît, passe à
        /// `sent`, porte `media` ; le contenu relu (déchiffré dans un salon chiffré) est identique,
        /// la vignette envoyée aussi, et `file(of:)` écrit les mêmes octets.
        private func imageRoundTrip(encrypted: Bool) async throws {
            try await withMediaSession(encrypted: encrypted) { session, roomID, directory in
                let timeline = try await openTimeline(roomID, in: session)
                let recorder = TimelineRecorder(timeline.items)
                defer { recorder.stop() }

                let png = try makePNG(width: 64, height: 64)
                let thumbnailPNG = try makePNG(width: 16, height: 16)
                let filename = "harness-\(UUID()).png"
                let fileURL = directory.appending(path: filename)
                try png.write(to: fileURL)

                let upload = try await timeline.send(
                    Attachment(
                        source: .file(fileURL),
                        kind: .image(dimensions: MediaDimensions(width: 64, height: 64), blurhash: nil),
                        mimeType: "image/png",
                        thumbnail: Attachment.Thumbnail(
                            source: .data(thumbnailPNG, filename: "thumbnail.png"),
                            mimeType: "image/png",
                            dimensions: MediaDimensions(width: 16, height: 16)
                        )
                    )
                )
                try await upload.waitUntilQueued()

                let snapshot = await recorder.waitUntil(within: .seconds(30)) { sentMessage(named: filename, in: $0) != nil }
                let message = try #require(snapshot.flatMap { sentMessage(named: filename, in: $0) }, "the image never reached .sent")
                let media = try #require(message.media)

                // L'écho `.sending` n'est pas exigé : `.bufferingNewest(1)` peut l'avoir sauté.
                #expect(message.sendState == .sent)
                #expect(message.eventID != nil)
                #expect(message.uploadProgress == nil)
                #expect(media.kind == .image)
                #expect(media.filename == filename)
                #expect(media.mimeType == "image/png")
                #expect(media.size == png.count)
                #expect(media.dimensions == MediaDimensions(width: 64, height: 64))
                #expect(media.source.url.hasPrefix("mxc://localhost/"), "source: \(media.source.url)")
                #expect(media.source.isEncrypted == encrypted)

                let content = try await session.media.content(of: media.source)
                #expect(content == png, "content: \(content.count) bytes, sent: \(png.count) bytes")

                let thumbnail = try #require(media.thumbnail, "the sent thumbnail is missing from the item")
                #expect(thumbnail.isEncrypted == encrypted)
                let thumbnailContent = try await session.media.content(of: thumbnail)
                #expect(thumbnailContent == thumbnailPNG)

                let file = try await session.media.file(of: media.source, filename: filename, mimeType: "image/png")
                #expect(try Data(contentsOf: file.url) == png)
            }
        }

        /// Vignette générée par Synapse (salon non chiffré : un serveur ne peut pas réduire un média
        /// chiffré), fichier temporaire lisible, déplacé par `persist(to:)`, supprimé à sa libération.
        @Test(.timeLimit(.minutes(2)))
        func thumbnailAndFileAreServed() async throws {
            try await withMediaSession(encrypted: false) { session, roomID, directory in
                let timeline = try await openTimeline(roomID, in: session)
                let recorder = TimelineRecorder(timeline.items)
                defer { recorder.stop() }

                let png = try makePNG(width: 64, height: 64)
                let filename = "harness-\(UUID()).png"
                let upload = try await timeline.send(
                    Attachment(
                        source: .data(png, filename: filename),
                        kind: .image(dimensions: MediaDimensions(width: 64, height: 64), blurhash: nil),
                        mimeType: "image/png"
                    )
                )
                try await upload.waitUntilQueued()
                let snapshot = await recorder.waitUntil(within: .seconds(30)) { sentMessage(named: filename, in: $0) != nil }
                let media = try #require(snapshot.flatMap { sentMessage(named: filename, in: $0)?.media })

                let thumbnail = try await session.media.thumbnail(of: media.source, width: 32, height: 32)
                let thumbnailImage = CGImageSourceCreateWithData(thumbnail as CFData, nil)
                    .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
                let decoded = try #require(thumbnailImage, "the thumbnail is not an image (\(thumbnail.count) bytes)")
                #expect(decoded.width >= 1 && decoded.width <= 64, "thumbnail width: \(decoded.width)")

                let file = try await session.media.file(of: media.source, filename: filename, mimeType: "image/png")
                #expect(FileManager.default.fileExists(atPath: file.url.path))
                #expect(try Data(contentsOf: file.url) == png)
                let destination = directory.appending(path: "kept-\(filename)")
                #expect(try file.persist(to: destination))
                #expect(try Data(contentsOf: destination) == png)

                var released: (any MediaFile)? = try await session.media.file(
                    of: media.source, filename: "released-\(filename)", mimeType: "image/png")
                let releasedURL = try #require(released?.url)
                #expect(FileManager.default.fileExists(atPath: releasedURL.path))
                released = nil
                #expect(
                    !FileManager.default.fileExists(atPath: releasedURL.path),
                    "the temporary file outlived its MediaFile: \(releasedURL.path)")
            }
        }

        /// Un fichier depuis `Data`, un audio et un message vocal gardent leur genre à la réception.
        @Test(.timeLimit(.minutes(2)))
        func dataFileAudioAndVoiceKeepTheirKind() async throws {
            try await withMediaSession(encrypted: false) { session, roomID, _ in
                let timeline = try await openTimeline(roomID, in: session)
                let recorder = TimelineRecorder(timeline.items)
                defer { recorder.stop() }

                let tag = UUID().uuidString
                let text = Data("MatrixClientKit harness \(tag)".utf8)
                // Le contenu d'un audio n'est pas décodé par le serveur : des octets quelconques
                // suffisent à éprouver le mappage du type de message.
                let sound = Data(repeating: 0x4F, count: 2048)
                let cases: [(filename: String, attachment: MatrixClientKit.Attachment, kind: MediaAttachment.Kind)] = [
                    (
                        "notes-\(tag).txt",
                        Attachment(source: .data(text, filename: "notes-\(tag).txt"), kind: .file, mimeType: "text/plain"),
                        .file
                    ),
                    (
                        "sound-\(tag).ogg",
                        Attachment(
                            source: .data(sound, filename: "sound-\(tag).ogg"), kind: .audio(duration: .seconds(2)),
                            mimeType: "audio/ogg"),
                        .audio
                    ),
                    (
                        "voice-\(tag).ogg",
                        Attachment(
                            source: .data(sound, filename: "voice-\(tag).ogg"),
                            kind: .voice(duration: .seconds(3), waveform: [0, 0.25, 0.5, 1]),
                            mimeType: "audio/ogg"),
                        .voice
                    ),
                ]

                for entry in cases {
                    let upload = try await timeline.send(entry.attachment)
                    try await upload.waitUntilQueued()
                }
                let snapshot = await recorder.waitUntil(within: .seconds(30)) { items in
                    cases.allSatisfy { sentMessage(named: $0.filename, in: items) != nil }
                }
                let items = try #require(snapshot, "not every media reached .sent")

                for entry in cases {
                    let media = try #require(sentMessage(named: entry.filename, in: items)?.media)
                    #expect(media.kind == entry.kind, "\(entry.filename): \(media.kind)")
                    #expect(media.mimeType == entry.attachment.mimeType)
                }
                let file = try #require(sentMessage(named: cases[0].filename, in: items)?.media)
                #expect(file.size == text.count)
                #expect(try await session.media.content(of: file.source) == text)
                let audio = try #require(sentMessage(named: cases[1].filename, in: items)?.media)
                #expect(audio.duration == .seconds(2))
                let voice = try #require(sentMessage(named: cases[2].filename, in: items)?.media)
                #expect(voice.duration == .seconds(3))
            }
        }

        /// `cancel()` juste après l'envoi : soit `waitUntilQueued()` lève `CancellationError` et
        /// l'écho disparaît sans jamais être envoyé, soit le média était déjà en file et part.
        ///
        /// L'annulation l'emporte dans `waitUntilQueued()` même si elle arrive juste après la mise
        /// en file : l'écho existe alors et c'est par son handle d'envoi qu'on l'abandonne, comme
        /// le documente ``AttachmentUpload/cancel()``.
        @Test(.timeLimit(.minutes(2)))
        func cancelledUploadIsConsistent() async throws {
            try await withMediaSession(encrypted: false) { session, roomID, _ in
                let timeline = try await openTimeline(roomID, in: session)
                let recorder = TimelineRecorder(timeline.items)
                defer { recorder.stop() }

                // Assez gros pour que l'envoi ne soit pas fini au moment de l'annulation.
                let filename = "large-\(UUID()).bin"
                let upload = try await timeline.send(
                    Attachment(
                        source: .data(randomData(count: 8 * 1024 * 1024), filename: filename),
                        kind: .file,
                        mimeType: "application/octet-stream"
                    )
                )
                upload.cancel()

                let outcome: Result<Void, any Error>
                do {
                    try await upload.waitUntilQueued()
                    outcome = .success(())
                } catch {
                    outcome = .failure(error)
                }

                switch outcome {
                case .success:
                    // Inatteignable avec `RustAttachmentUpload` : `cancel()` précède l'attente et
                    // l'annulation l'emporte toujours. Gardé pour une implémentation qui
                    // laisserait gagner une mise en file antérieure.
                    let sent = await recorder.waitUntil(within: .seconds(30)) { sentMessage(named: filename, in: $0) != nil }
                    #expect(sent != nil, "waitUntilQueued() returned but the media never reached .sent")
                case let .failure(error) where error is CancellationError:
                    // Mise en file battue par l'annulation : aucun écho n'apparaît. Sinon, l'écho
                    // finit par être là et s'abandonne par son handle. Sondé jusqu'à 3 s plutôt
                    // que lu une fois : l'écho peut arriver après une lecture trop précoce.
                    let withEcho = await recorder.waitUntil(within: .seconds(3)) { items in
                        items.contains { $0.message?.media?.filename == filename }
                    }
                    if let echo = withEcho?.first(where: { $0.message?.media?.filename == filename }) {
                        try await cancelThroughEcho(echo, of: filename, in: timeline, recorder: recorder)
                    } else {
                        try await expectGone(
                            recorder, "the cancelled upload",
                            matching: { $0.message?.media?.filename == filename })
                    }
                case let .failure(error):
                    Issue.record("waitUntilQueued() threw \(error) after cancel()")
                }
            }
        }

        /// Un média en file, pendant son upload : `sendHandle(for:)` sur son écho, puis `cancel()`.
        /// `true` → l'écho disparaît et le média n'atteint jamais `sent` ; `false` → il est envoyé.
        /// Données aléatoires : rien ne se compresse ni ne se déduplique côté serveur.
        @Test(.timeLimit(.minutes(2)))
        func cancelDuringUploadStopsIt() async throws {
            try await withMediaSession(encrypted: false) { session, roomID, _ in
                let timeline = try await openTimeline(roomID, in: session)
                let recorder = TimelineRecorder(timeline.items)
                defer { recorder.stop() }

                let filename = "uploading-\(UUID()).bin"
                let upload = try await timeline.send(
                    Attachment(
                        source: .data(randomData(count: 16 * 1024 * 1024), filename: filename),
                        kind: .file,
                        mimeType: "application/octet-stream"
                    )
                )
                try await upload.waitUntilQueued()
                let uploading = await recorder.waitUntil(within: .seconds(30)) { items in
                    items.contains { $0.message?.media?.filename == filename && $0.message?.uploadProgress != nil }
                }
                let echo = try #require(
                    uploading?.first { $0.message?.media?.filename == filename },
                    "no upload progress observed: \(describe(recorder.latest))")
                #expect(echo.message?.sendState == .sending)

                try await cancelThroughEcho(echo, of: filename, in: timeline, recorder: recorder)
            }
        }

        /// `SendHandle.cancel()` sur un texte : `true` → l'écho disparaît et n'est jamais envoyé ;
        /// `false` → le message est envoyé.
        @Test(.timeLimit(.minutes(2)))
        func cancelledTextIsConsistent() async throws {
            try await withMediaSession(encrypted: false) { session, roomID, _ in
                let timeline = try await openTimeline(roomID, in: session)
                let recorder = TimelineRecorder(timeline.items)
                defer { recorder.stop() }

                let body = "harness-cancel-\(UUID())"
                let handle = try await timeline.send(.text(body))
                let cancelled = try await handle.cancel()

                if cancelled {
                    try await expectGone(recorder, "the cancelled text", matching: { $0.message?.body == body })
                } else {
                    let sent = await recorder.waitUntil(within: .seconds(30)) { items in
                        items.contains { $0.message?.body == body && $0.message?.sendState == .sent }
                    }
                    #expect(sent != nil, "cancel() returned false but the text never reached .sent")
                }
            }
        }

        /// `sendHandle(for:)` rend le handle d'un écho local — en échec ici, dans un salon dont les
        /// niveaux interdisent `m.room.message` à la créatrice elle-même, pour que l'écho ne parte
        /// jamais — y compris depuis une seconde timeline, dont le premier diff est un `reset` (le
        /// chemin d'un relancement). Un élément envoyé ou distant n'en a pas.
        @Test(.timeLimit(.minutes(2)))
        func sendHandleLookupForLocalEcho() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            let forbiddenRoom = try await createRoom(
                on: configuration.passwordHomeserver, user: configuration.user, password: configuration.password,
                encrypted: false, powerLevels: ["events": ["m.room.message": 101]], roomVersion: "11"
            )
            try await withMediaSession(encrypted: false) { session, roomID, _ in
                // Écho en échec : le serveur refuse l'événement (403), l'écho reste local.
                let failing = try await openTimeline(forbiddenRoom, in: session)
                let failingRecorder = TimelineRecorder(failing.items)
                defer { failingRecorder.stop() }
                let refused = "harness-refused-\(UUID())"
                try await failing.send(.text(refused))
                let failedSnapshot = await failingRecorder.waitUntil(within: .seconds(30)) { items in
                    items.contains { $0.message?.body == refused && $0.message?.sendState.isFailed == true }
                }
                let failedItem = try #require(
                    failedSnapshot?.first { $0.message?.body == refused },
                    "the refused text never failed: \(describe(failingRecorder.latest))")
                #expect(failedItem.message?.sendState.isRecoverableFailure == false)
                #expect(failing.sendHandle(for: failedItem) != nil, "no handle for a failed local echo")

                // Seconde timeline : l'écho en échec arrive dans le `reset` initial.
                let reopened = try await openTimeline(forbiddenRoom, in: session)
                let reopenedRecorder = TimelineRecorder(reopened.items)
                defer { reopenedRecorder.stop() }
                let reopenedSnapshot = await reopenedRecorder.waitUntil(within: .seconds(15)) { items in
                    items.contains { $0.message?.body == refused }
                }
                let reopenedItem = try #require(
                    reopenedSnapshot?.first { $0.message?.body == refused }, "the failed echo is missing after reopening")
                let reopenedHandle = try #require(
                    reopened.sendHandle(for: reopenedItem), "no handle for a failed echo seen through the initial reset")

                // Abandon : l'écho disparaît des deux timelines.
                #expect(try await reopenedHandle.cancel())
                try await expectGone(failingRecorder, "the abandoned echo", matching: { $0.message?.body == refused })

                // Écho en cours d'envoi : le handle existe tant que l'élément n'est pas `sent`.
                let timeline = try await openTimeline(roomID, in: session)
                let items = timeline.items
                let recorder = TimelineRecorder(timeline.items)
                defer { recorder.stop() }
                let body = "harness-lookup-\(UUID())"
                try await timeline.send(.text(body))
                let echo = await firstValue(of: items, within: .seconds(30)) { items in
                    items.contains { $0.message?.body == body }
                }
                let echoItem = try #require(echo?.first { $0.message?.body == body }, "the local echo never appeared")
                let echoHandle = timeline.sendHandle(for: echoItem)
                if echoItem.message?.sendState == .sending, echoHandle == nil {
                    // Toléré par la spec : l'élément a pu passer à `sent` entre le diff et la lecture.
                    let sent = await recorder.waitUntil(within: .seconds(30)) { items in
                        items.contains { $0.message?.body == body && $0.message?.sendState == .sent }
                    }
                    #expect(sent != nil, "no handle for a sending echo that never reached .sent")
                }

                // Élément envoyé : plus de handle, ni pour cette timeline ni pour une autre.
                let sentSnapshot = await recorder.waitUntil(within: .seconds(30)) { items in
                    items.contains { $0.message?.body == body && $0.message?.sendState == .sent }
                }
                let sentItem = try #require(
                    sentSnapshot?.first { $0.message?.body == body }, "the text never reached .sent")
                #expect(timeline.sendHandle(for: sentItem) == nil)

                let remote = try await openTimeline(roomID, in: session)
                let remoteRecorder = TimelineRecorder(remote.items)
                defer { remoteRecorder.stop() }
                let remoteSnapshot = await remoteRecorder.waitUntil(within: .seconds(15)) { items in
                    items.contains { $0.message?.body == body }
                }
                let remoteItem = try #require(remoteSnapshot?.first { $0.message?.body == body })
                #expect(remote.sendHandle(for: remoteItem) == nil)
            }
        }

        @Test(.timeLimit(.minutes(2)))
        func maxUploadSizeIsPositive() async throws {
            try await withMediaSession(encrypted: false) { session, _, _ in
                let size = try await session.media.maxUploadSize()
                #expect(size > 0, "maxUploadSize: \(size)")
            }
        }

        /// Spec §5 : l'application garde des services, une timeline et ses flux, un handle de room,
        /// le service média et un fichier média après la session. `logout()`, la session libérée,
        /// puis le reste : le processus de test ne doit pas s'arrêter.
        @Test(.timeLimit(.minutes(2)))
        func servicesKeptAfterLogoutDoNotCrash() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            let directory = newHarnessDirectory()
            defer { removeDirectory(directory) }
            let roomID = try await createRoom(
                on: configuration.passwordHomeserver, user: configuration.user, password: configuration.password,
                encrypted: true
            )

            var session: (any MatrixSession)? = try await signedInSession(
                configuration, directory: directory, deviceName: "Harness (lifetime)")
            // Sonde faible : prouve que la session est vraiment libérée avant ses dépendants.
            weak var sessionProbe: AnyObject? = session.map { $0 as AnyObject }
            var room: (any RoomHandle)?
            var timeline: (any Timeline)?
            var items: AsyncStream<[TimelineItem]>?
            var recorder: TimelineRecorder?
            var media: (any MediaService)?
            var mediaFile: (any MediaFile)?
            var rooms: (any RoomService)?
            var sync: (any SyncController)?
            var encryption: (any EncryptionService)?
            var notifications: (any NotificationService)?

            do {
                let opened = try #require(session)
                let joined = await firstValue(of: opened.rooms.list(filter: .joined), within: .seconds(20)) { rooms in
                    rooms.contains { $0.id == roomID }
                }
                try #require(joined != nil, "the room never appeared")
                let openedRoom = try await opened.rooms.room(roomID)
                room = openedRoom
                let openedTimeline = try await openedRoom.timeline()
                timeline = openedTimeline
                items = openedTimeline.items
                let openedRecorder = TimelineRecorder(openedTimeline.items)
                recorder = openedRecorder

                let png = try makePNG(width: 16, height: 16)
                let filename = "lifetime-\(UUID()).png"
                let upload = try await openedTimeline.send(
                    Attachment(source: .data(png, filename: filename), kind: .image(dimensions: nil, blurhash: nil), mimeType: "image/png")
                )
                try await upload.waitUntilQueued()
                let snapshot = await openedRecorder.waitUntil(within: .seconds(30)) {
                    sentMessage(named: filename, in: $0) != nil
                }
                let source = try #require(snapshot.flatMap { sentMessage(named: filename, in: $0)?.media?.source })

                media = opened.media
                mediaFile = try await opened.media.file(of: source, filename: filename, mimeType: "image/png")
                rooms = opened.rooms
                sync = opened.sync
                encryption = opened.encryption
                notifications = opened.notifications
            } catch {
                if let opened = session {
                    await cleaningUp {
                        await opened.sync.stop()
                        try? await opened.logout()
                    }
                }
                throw error
            }

            if let opened = session {
                await cleaningUp {
                    await opened.sync.stop()
                    try? await opened.logout()
                }
            }
            session = nil
            try await Task.sleep(for: .seconds(1))
            for _ in 0..<40 where sessionProbe != nil {
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(sessionProbe == nil, "the session is still alive: the dependents would not be the last holders")

            // La session est partie : le `Client` FFI ne vit plus que par ce qui reste ici.
            #expect(timeline != nil && room != nil && media != nil && mediaFile != nil && items != nil)
            #expect(rooms != nil && sync != nil && encryption != nil && notifications != nil)
            recorder?.stop()
            recorder = nil
            items = nil
            mediaFile = nil
            timeline = nil
            room = nil
            media = nil
            rooms = nil
            sync = nil
            encryption = nil
            notifications = nil
            try await Task.sleep(for: .seconds(1))
        }

        /// La timeline libérée alors que son flux `items` est encore itéré et que des mises à jour
        /// arrivent — envoyées par une seconde timeline de la même session. Vise le `deinit` de la
        /// timeline exécuté dans son propre rappel de listener (référence faible promue le temps
        /// d'un diff) : au mieux de ce qu'un test peut provoquer, d'où plusieurs tours.
        @Test(.timeLimit(.minutes(2)))
        func timelineReleasedWhileItsItemsAreIteratedDoesNotCrash() async throws {
            try await withMediaSession(encrypted: false) { session, roomID, _ in
                let sender = try await openTimeline(roomID, in: session)
                let senderRecorder = TimelineRecorder(sender.items)
                defer { senderRecorder.stop() }

                for round in 0..<10 {
                    var released: (any Timeline)? = try await openTimeline(roomID, in: session)
                    let releasedRecorder = TimelineRecorder(try #require(released).items)
                    defer { releasedRecorder.stop() }

                    let prefix = "harness-release-\(round)-\(UUID())-"
                    let burst = Task {
                        for index in 0..<10 {
                            try await sender.send(.text("\(prefix)\(index)"))
                        }
                    }
                    let started = await releasedRecorder.waitUntil(within: .seconds(30)) { items in
                        items.contains { $0.message?.body.hasPrefix(prefix) == true }
                    }
                    #expect(started != nil, "round \(round): the burst never reached the timeline")

                    // Libérée en plein flot de diffs, flux toujours itéré par l'enregistreur.
                    released = nil

                    try await burst.value
                    let delivered = await senderRecorder.waitUntil(within: .seconds(30)) { items in
                        (0..<10).allSatisfy { index in
                            items.contains { $0.message?.body == "\(prefix)\(index)" && $0.message?.sendState == .sent }
                        }
                    }
                    #expect(delivered != nil, "round \(round): the burst was not fully sent")
                    // Laisse arriver les derniers diffs sur le flux orphelin.
                    try await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }
}

// MARK: - Outils du cas

/// Ouvre une session neuve sur `synapse-password` dans un salon créé pour l'occasion, exécute
/// `body`, puis arrête la sync et déconnecte la session, que `body` ait réussi ou non.
private func withMediaSession(
    encrypted: Bool,
    _ body: (any MatrixSession, RoomID, URL) async throws -> Void
) async throws {
    let configuration = try #require(HarnessConfiguration.current)
    let directory = newHarnessDirectory()
    defer { removeDirectory(directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let roomID = try await createRoom(
        on: configuration.passwordHomeserver, user: configuration.user, password: configuration.password,
        encrypted: encrypted
    )

    let session = try await signedInSession(configuration, directory: directory, deviceName: "Harness (media)")
    let outcome: Result<Void, any Error>
    do {
        try await body(session, roomID, directory)
        outcome = .success(())
    } catch {
        outcome = .failure(error)
    }
    await cleaningUp {
        await session.sync.stop()
        try? await session.logout()
    }
    try outcome.get()
}

/// Session connectée sur `synapse-password`, sync en cours.
private func signedInSession(
    _ configuration: HarnessConfiguration, directory: URL, deviceName: String
) async throws -> any MatrixSession {
    let client = Matrix.client(homeserver: configuration.passwordHomeserver, storage: .local(directory: directory))
    let session = try await client.login(
        .password(username: configuration.user, password: configuration.password, deviceName: deviceName)
    )
    let states = session.sync.state
    await session.sync.start()
    let state = await waitUntilRunning(states)
    guard state == .running else {
        await cleaningUp {
            await session.sync.stop()
            try? await session.logout()
        }
        throw MatrixError.unexpected(message: "sync reached \(String(describing: state))", details: nil)
    }
    return session
}

/// La timeline d'un salon, une fois que la sync l'a remonté (`room(_:)` ne résout que ceux-là).
private func openTimeline(
    _ roomID: RoomID, in session: any MatrixSession, sourceLocation: SourceLocation = #_sourceLocation
) async throws -> any Timeline {
    let joined = await firstValue(of: session.rooms.list(filter: .joined), within: .seconds(20)) { rooms in
        rooms.contains { $0.id == roomID }
    }
    try #require(
        joined != nil, "room \(roomID.rawValue) never appeared in the joined list", sourceLocation: sourceLocation)
    return try await session.rooms.room(roomID).timeline()
}

/// Le message `sent` qui porte le média nommé `filename`.
private func sentMessage(named filename: String, in items: [TimelineItem]) -> Message? {
    items.compactMap(\.message).last { $0.media?.filename == filename && $0.sendState == .sent }
}

/// Attend que plus aucun élément ne corresponde, puis vérifie qu'il ne revient pas et qu'aucun
/// n'a jamais été `sent` : une annulation acceptée ne doit rien laisser partir.
private func expectGone(
    _ recorder: TimelineRecorder,
    _ what: String,
    within timeout: Duration = .seconds(30),
    matching predicate: @escaping @Sendable (TimelineItem) -> Bool
) async throws {
    // L'écho peut apparaître et disparaître entre deux instantanés (`.bufferingNewest(1)`) : son
    // passage n'est pas exigé, seule son absence l'est.
    let gone = await recorder.waitUntil(within: timeout) { !$0.contains(where: predicate) }
    #expect(gone != nil, "\(what) is still in the timeline: \(describe(recorder.latest))")
    try await Task.sleep(for: .seconds(3))
    #expect(
        !(recorder.latest ?? []).contains(where: predicate), "\(what) came back: \(describe(recorder.latest))")
    #expect(
        !recorder.everSaw { predicate($0) && $0.message?.sendState == .sent },
        "\(what) was sent anyway")
}

/// Les messages d'un instantané, pour les messages d'échec.
private func describe(_ items: [TimelineItem]?) -> String {
    guard let items else { return "no snapshot" }
    return items.compactMap(\.message)
        .map { "\($0.media?.filename ?? $0.body) [\($0.sendState)]" }
        .joined(separator: ", ")
}

/// Abandonne un média en file par le handle d'envoi de son écho, et vérifie l'état final : écho
/// disparu et jamais `sent` si l'abandon a pris, média `sent` sinon.
private func cancelThroughEcho(
    _ echo: TimelineItem, of filename: String, in timeline: any Timeline, recorder: TimelineRecorder
) async throws {
    let handle = try #require(timeline.sendHandle(for: echo), "no send handle for the queued media's echo")
    if try await handle.cancel() {
        try await expectGone(
            recorder, "the media cancelled through its echo", matching: { $0.message?.media?.filename == filename })
    } else {
        let sent = await recorder.waitUntil(within: .seconds(30)) { sentMessage(named: filename, in: $0) != nil }
        #expect(sent != nil, "cancel() returned false but the media never reached .sent")
    }
}

/// `count` octets aléatoires.
private func randomData(count: Int) -> Data {
    var data = Data(count: count)
    data.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, count) }
    return data
}

/// Un PNG RGBA de `width` × `height`, construit en mémoire : Synapse a besoin d'une vraie image
/// pour en tirer une vignette, et aucune ressource binaire n'est versionnée.
private func makePNG(width: Int, height: Int) throws -> Data {
    let context = try #require(
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    context.setFillColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(red: 0.9, green: 0.5, blue: 0.1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
    let image = try #require(context.makeImage())

    let data = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
    return data as Data
}

/// Itère un flux `items` en tâche de fond et garde chaque instantané reçu : les assertions portent
/// sur le dernier, ou sur tout l'historique (« l'écho a-t-il été vu ? »).
private final class TimelineRecorder: Sendable {
    private final class Log: Sendable {
        let snapshots = Mutex<[[TimelineItem]]>([])
    }

    private let log: Log
    private let task: Task<Void, Never>

    init(_ items: AsyncStream<[TimelineItem]>) {
        let log = Log()
        self.log = log
        self.task = Task {
            for await snapshot in items {
                log.snapshots.withLock { $0.append(snapshot) }
            }
        }
    }

    deinit {
        task.cancel()
    }

    /// Le dernier instantané, `nil` avant le premier.
    var latest: [TimelineItem]? {
        log.snapshots.withLock { $0.last }
    }

    func everSaw(_ predicate: (TimelineItem) -> Bool) -> Bool {
        let snapshots = log.snapshots.withLock { $0 }
        return snapshots.contains { $0.contains(where: predicate) }
    }

    /// Le premier dernier-instantané qui satisfait `predicate`, sondé toutes les 100 ms ; `nil`
    /// après `timeout`.
    func waitUntil(within timeout: Duration, _ predicate: ([TimelineItem]) -> Bool) async -> [TimelineItem]? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let latest, predicate(latest) { return latest }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    /// Termine l'itération ; le flux est alors libéré et sa souscription amont annulée.
    func stop() {
        task.cancel()
    }
}
