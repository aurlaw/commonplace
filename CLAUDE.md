# Commonplace

iOS app (iPhone only, iOS 26+): a personal structured journal. SwiftUI + SwiftData, synced through the private CloudKit database `iCloud.com.aurlaw.commonplace`.

Phase briefs live in the Tech Obsidian vault under `commonplace/phases/`.

## Layout

- `Commonplace.xcodeproj` — Xcode project. **Never edit it** (including `project.pbxproj`)
- `Commonplace/` — app sources
  - `Models/` — `SchemaV2` models (`Topic`, `Entry`, `Photo`, `Route`), the frozen `SchemaV1`, and `TopicColor` (Foundation only, no SwiftUI)
  - `Persistence/` — `ModelContainerFactory`, `ModelContext.saveOrRollback()`, `LastUsedTopic`, `ImageProcessor` (with `PhotoLimits` and `ImageDownsampler`), `LocationService`, `LocationCapture`, `TranscriptionService` (with `AudioLevelMeter` and `DictationRule`), `EntrySearch`, `BiometricAuthenticator`, `AppLock`, `LinkMetadataService` (with `CachedLinkMetadataService`), `TextCleaner` (with `FoundationModelsCleaner`), `GPXParser` (with `RouteLimits`), `RouteMetrics` (with `RoutePath`, `RouteProfile`), `RouteImporter` (with `RouteDraft`, `GPXRouteImporter`, and `RouteOperations`), and `TrashOperations` (with `TrashRetention`)
  - `DesignSystem/` — shared components (`TopicRow`, `EntryRow`, `TopicHeader`, `TopicChip`, `ThumbnailStrip`, `PhotoGrid`, `ZoomablePhotoPage`, `FormattedBody`, `LinkPreviews`) and the pure `EntryTimeline`, photo zoom (`PhotoZoom.swift`: `PhotoZoom`, `PhotoViewerState`), the topic map (`TopicMap.swift`: `TopicMapModel`, `MapPin`, `MapGroup`, `TopicMapStyle`), search (`Search.swift`: `SearchableText`, `SearchQuery`, `SearchSnippet`, `SearchResults`), Markdown helpers (`MarkdownBody`, `MarkdownEditing`), and Clean Up helpers (`CleanUp.swift`: `CleanUpChunks`, `CleanUpCheck`, `CleanUpRunner`)
  - `Screens/` — one file per screen or sheet; `RootView` owns the navigation stack
  - `SampleData/` — the seed, placeholder images, `PreviewContainer`, `FakeLocationService`, `FakeTranscriptionService`, `FakeBiometricAuthenticator`, `FakeLinkMetadataService`, `FakeTextCleaner`, and `SampleRoutes` (synthetic GPX tracks, with `FakeRouteImporter`)
- `CommonplaceTests/` — unit tests (Swift Testing), hosted in the app
- `CommonplaceUITests/` — UI tests; not run by `make test`
- `docs/design/` — design reference exports

The project uses folder-synchronized groups: Swift files created under `Commonplace/` and `CommonplaceTests/` are picked up automatically. If something can only be done in the project file (settings, capabilities, signing, targets), stop and list it as a manual step for Michael.

## Build, test, lint

Use the Makefile, never raw `xcodebuild`:

- `make build` — build for the simulator
- `make test` — run `CommonplaceTests`
- `make lint` — `swift-format lint --strict` (config in `.swift-format`, 4-space indentation)

`SIMULATOR` is overridable: `make test SIMULATOR="iPhone 17 Pro"`.

No device builds, signing or capability changes, git operations, or CloudKit Console actions.

## Dependencies

No third-party packages, including test helpers and formatters. Apple frameworks only: SwiftUI, SwiftData, PhotosUI, ImageIO, CoreImage, Speech, AVFoundation, CoreLocation, MapKit, LocalAuthentication, LinkPresentation (link previews only), FoundationModels (Clean Up only, on-device `SystemLanguageModel`), Charts (the route elevation profile only), UniformTypeIdentifiers.

## Concurrency (Swift 6)

The app target uses **default MainActor isolation** and Approachable Concurrency.

- Views stay main-actor (the default)
- Pure value types and helpers used off the main actor (`TopicColor`, `ModelContainerFactory`) are marked `nonisolated`
- `@Model` classes carry no isolation annotations. Verified in Xcode 27.0 (and 26.6 before it): they compile as-is under default MainActor isolation, and they can be created and read from nonisolated code. They are not `Sendable` — never pass a model across actors; pass its `PersistentIdentifier` instead
- An extension of a `nonisolated` value type is main-actor by default (seen in Xcode 27.0 with `TopicColor`). Write `nonisolated extension` when its members must be usable from nonisolated code
- No `@unchecked Sendable`, no `nonisolated(unsafe)`
- The test target does **not** have default MainActor isolation: annotate test suites that use a `ModelContext` with `@MainActor`

## Toolchain

Built with Xcode 27 (iOS 27 SDK); the deployment target is **iOS 26**. Any API newer than iOS 26 needs an `#available` check with an iOS 26 fallback.

## UI

- Chrome is system chrome: navigation bars, toolbars, sheets, menus, and the system button styles. No custom glass effects
- The only color in content is the topic's own (a bar, a dot, or the 14% header tint); the accent stays system blue
- **Palette:** `TopicColor` has eight cases — red, orange, brown, green, teal, indigo, purple, pink — default `.indigo`. Each maps to the matching SwiftUI system color in `DesignSystem/TopicColor+Color.swift`; there are no asset-catalog colors. Blue is reserved for the accent. An unknown stored raw value falls back to the default
- Date strings and timeline ordering come from `EntryTimeline` (`groupByMonth`, `neighbors`, `lastEntryLabel`, …), which is `nonisolated` and unit-tested. Don't format dates inline in views
- Relative labels ("Today", "Yesterday") read the `referenceDate` environment value, falling back to the real clock when it is `nil`

### Saving

Save explicitly after each user action with `modelContext.saveOrRollback()` rather than relying on autosave, so the change reaches the store (and CloudKit) promptly. It returns the error message on failure, after rolling the context back; show it with `.saveErrorAlert(_:)`.

Editing sheets work on a draft value (`TopicDraft`, `EntryDraft`) and write to the model only on save. Keep the draft-to-model logic (`trimmed` / `trimmedBody`, `isValid`, `isDirty(comparedTo:)`, `makeTopic()` / `makeEntry()`, `apply(to:)`) on the draft, where it is unit-tested, not inline in the view.

Both sheets confirm "Discard changes?" on Cancel when the draft is dirty and set `interactiveDismissDisabled(isDirty)`. SwiftUI has no callback for an attempted swipe-dismiss, so with unsaved changes the swipe is blocked and Cancel is the way out.

### Entries

- **An entry needs a topic, and text or at least one photo.** Save is disabled until then, and while picked photos are still processing
- The body is trimmed of leading and trailing whitespace and newlines on save; inner line breaks are kept
- **No future dates:** the date picker ends at the moment the composer opened. Back-dating is fine
- **Moving an entry to another topic** (since I7b) is reassigning `Entry.topic`; no schema change, and it syncs like any edit. Two ways in: the Edit Entry composer shows the topic picker in edit mode too (archived topics in their own section; Cancel undoes the move), and **Move to…** (`MoveToMenu`) in the entry detail ••• menu and the timeline row context menu
- Destinations come from `TopicDestinations`: live topics other than the entry's own, non-archived by recent activity, then archived. One-step moves go through `EntryOperations.move(_:to:)`; the composer moves through `EntryDraft.apply(to:)` in its single save
- **Everything travels with the entry:** photos, location, date, body. The destination's `capturesLocation` setting never adds or removes a location, and in edit mode `setTopic(_:)` leaves the draft's location state untouched. The last-used topic doesn't change on a move. Only live entries move
- After a move, entry detail falls back like it does for a trashed entry (neighbor, or back to the topic) and shows a short "Moved to …" confirmation (`.transientMessage(_:)`, announced to VoiceOver)
- `EntryDraft.apply(to:)` writes the date, the body, and a changed topic — never photos, location, `createdAt`, or `deletedAt`
- Dictation state and its grey pending text are never written to the body; only finals are (see Dictation)
- **Last-used topic** is a per-device preference in `@AppStorage(LastUsedTopic.storageKey)`: the topic's `PersistentIdentifier` as JSON, not synced. It is recorded when a **new** entry is saved (edits don't change it). "+ Entry" on the topics list opens on it if it is still live and not archived, otherwise on the first topic by recent activity; the rules are in `LastUsedTopic.resolve(stored:among:)`
- **Topic screens read entries through the `Topic.entries` relationship**, not an `@Query`. `EntryDraftTests` checks that saving an entry into a topic, and editing one, is reported through Observation on the same context, which is what refreshes the timeline, the list row, and entry detail. If a screen is ever seen not to refresh (for example after a CloudKit import), switch that screen to an `@Query` filtered by topic rather than forcing a refresh

### Topics list

- **Sort By** (Recent Activity or Name) is a per-device preference in `@AppStorage("topicSort")`, stored as the `TopicSort` raw value and not synced. An unknown stored value falls back to Recent Activity. It applies to both the live and Archived sections, through `TopicListSections`
- Sorting is done in memory, because Recent Activity depends on the computed `lastEntryDate`
- Duplicate topic titles are allowed
- Archived topics stay fully usable; archiving only moves them to the Archived section

### Photos

- **Library only, no camera.** `PhotosPicker` runs out of process, so there are no photo-library or camera usage descriptions and no `PHPhotoLibrary` authorization
- The picker uses `preferredItemEncoding: .compatible`, so Photos hands over a converted copy rather than the original file. This is deliberate: RAW and some imported TIFF-based photos failed to downsample as originals
- **Sizes and limits are constants in `PhotoLimits`:** stored image ≤ 3000 px long edge at JPEG 0.8, thumbnail ≤ 400 px at JPEG 0.7, at most 20 photos per entry. The picker's selection limit is the remaining slots, and `EntryDraft.addPhoto(_:)` enforces the limit too
- **`ImageProcessor`** (protocol, injected through the `imageProcessor` environment value; `ImageIOProcessor` is the real one) turns picked data into a `ProcessedImage`. It downsamples with ImageIO, bakes in EXIF orientation, never upscales, and drops all metadata including GPS. When `CGImageSourceCreateThumbnailAtIndex` fails (seen on a device with imported, TIFF-based RAW photos, which ImageIO could neither thumbnail nor decode), `ImageDownsampler` falls back in order to: Core Image's RAW pipeline (`CIRAWFilter`), the largest image in the file ImageIO can decode, and last the file's embedded preview, which may be small. The fallbacks use much more memory than the fast path. `process` is `@concurrent`, so it runs off the main actor; picked photos are processed one at a time, in pick order
- **`DraftPhoto`** is what the composer holds: `.existing(Photo)` for saved photos and `.new(id:image:thumbnail:)` for picked ones. New photos are values, not inserted models, until Save, so Cancel or a failed save can't leave orphaned `Photo` records
- `EntryDraft.applyPhotos(to:in:)` makes the entry's photos match the draft for new and edited entries alike: it inserts new photos, deletes dropped ones, and rewrites `order` 0…n-1. It touches nothing else on the entry. Adding or removing a photo makes the draft dirty
- **Photo hard-delete exception:** removing a photo in the composer calls `modelContext.delete(photo)` on Save, with no Trash and no confirmation. With removing a route (see Routes), one of the two deletes outside `TrashOperations`. Cancel discards the removal
- **Never show a full-size bitmap in a grid or strip.** Small tiles and strips use `thumbnailData` through `PhotoImage`. Anything larger uses `DownsampledPhotoImage`, which decodes `imageData` off the main actor at a stated pixel size and shows the thumbnail until it is ready (and whenever `imageData` is still `nil` after a sync). The viewer keeps a full-size bitmap for the visible page only

### Photo viewer zoom

- **`ZoomablePhotoPage`** is one viewer page: a `UIScrollView` in a `UIViewRepresentable` zooming a `UIImageView` (`viewForZooming`), sized to fit the bounds at scale 1 and centered with `contentInset` while smaller than them. Chosen over pure SwiftUI gestures because it gives pinch around the fingers, momentum, edge and zoom bounce for free, and at fit its content fits the bounds, so it doesn't take horizontal pans and the page-style `TabView` still swipes. The image follows the `DownsampledPhotoImage` rules through the shared `loadsDownsampledImage(of:maxPixelSize:isActive:into:)`: full-size bitmap only for the active page, thumbnail until it's ready; no extra decode at higher zoom
- **Limits** (`PhotoZoom`, pure and tested): 1× (fit) to 4×; releasing below fit springs back. Double-tap at fit zooms to 2.5× on the tapped point (`doubleTapRect`, kept inside the content); zoomed, double-tap returns to fit. Double-tap and VoiceOver zooms skip the animation with Reduce Motion
- **Paging rule** (`PhotoViewerState`, pure and tested): zoomed (scale above fit, with a small tolerance) suspends paging with `.scrollDisabled` on the pager; panning to a zoomed photo's edge never pages. Changing the selection (swipe or filmstrip) resets the zoom to fit and brings the chrome back; only the selected page gets the zoom binding, and out-of-view pages reset to fit. The page reports its scale when it crosses fit and when a zoom ends, not every frame, so the viewer doesn't re-render through a pinch. **Verified on a device:** `.scrollDisabled` stops the page-style `TabView` from paging while zoomed, swiping pages again at fit, and the chrome toggle and zoom reset work as described
- **Chrome toggle:** a single tap (recognized once the double-tap fails, so slightly delayed) hides or shows the navigation bar (`.toolbarVisibility`, which carries the counter and caption), the filmstrip, and the status bar, with a fade. Hiding the bar changes the page's bounds; the page refits keeping its zoom and visible center, as it does on rotation
- **VoiceOver:** each page keeps "Photo 2 of 6", adds `accessibilityZoomAction` (whole steps, `PhotoZoom.steppedScale`, announced "Zoomed in" / "Zoomed out"), and a "Hide controls" / "Show controls" action

### Dictation

- **On-device only:** `SpeechAnalyzer` with a `SpeechTranscriber` module (`.volatileResults` reporting), in the device's locale mapped through `SpeechTranscriber.supportedLocale(equivalentTo:)`. No server recognition, no `SFSpeechRecognizer` fallback, no time limit, no audio written to disk, no background audio mode
- **`TranscriptionService`** (protocol, injected through the `transcriptionService` environment value): `availability()`, `requestPermission()`, `installModel()` (progress 0…1), `start()` → `AsyncStream<TranscriptionEvent>` (`.volatile`, `.final`, `.level`, `.ended`), and `stop()`, which finalizes so the last volatile text arrives as `.final` before `.ended`. Abandoning the stream (cancelling the task reading it) tears the session down without finalizing. `SpeechTranscriptionService` (an actor) is the real one; `FakeTranscriptionService` (scripted events, configurable availability, permission, install progress and failures) is used by tests, previews, shell mode, and the hosted test run, and `.sampleData()` injects it. The composer keeps the service a dictation started on (`activeTranscription`) and stops that one
- **Speech model:** `AssetInventory.status(forModules:)` decides `.needsModel`; the first mic tap downloads it through `AssetInventory.assetInstallationRequest(supporting:)` → `downloadAndInstall()`, with progress polled from the request's `Progress` and shown in the dictation control. A failed download (offline) shows "Connect to the internet once to download dictation"; once installed, dictation works offline
- **Permissions:** microphone access (`AVAudioApplication.requestRecordPermission()`) is asked at the first mic tap, never at launch. Denied → an alert with Open Settings. **Whether `SpeechTranscriber` also needs `SFSpeechRecognizer` authorization is unverified** `[NEEDS VERIFICATION]`: the iOS 27 SDK's Speech interface says nothing about it, so the app asks for the microphone only. `SpeechTranscriptionService.requestsSpeechRecognitionAuthorization` (currently `false`) turns the extra request and status check on if a device shows it is needed. Record the finding here once checked
- **Audio format conversion rule:** the microphone's format usually differs from what the analyzer accepts, and a mismatch fails silently. The target comes from `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`, and every tap buffer is converted with `AVAudioConverter` before it is wrapped in `AnalyzerInput`
- **Real-time thread rule:** the input tap runs on a real-time audio thread. Its block is built in a `nonisolated static` function (`makeTap`) so it isn't actor-isolated, and it captures only what it is given — the converter, the target format, and the two stream continuations — never actor or main-actor state. Buffers reach the analyzer through its input stream; levels reach the UI through the event stream
- **Level:** RMS of each buffer → decibels mapped to 0…1 (floor −50 dB) → smoothed → throttled to about 20 updates a second, in `AudioLevelMeter` (pure and tested)
- **Audio session:** `.record` with the `.spokenAudio` mode (falling back to `.default` if the mode is refused), deactivated with `.notifyOthersOnDeactivation` so paused music resumes. Interruptions, the input device going away or appearing, and engine configuration changes stop dictation, keeping every final; so does the scene leaving `.active`. Dismissing the sheet cancels the session
- **States** (`EntryDraft.Dictation`): `.idle`, `.preparing` (availability and permission), `.downloading(progress:)`, `.listening(pending:elapsedSeconds:level:)`, `.finishing(pending:)`, `.unavailable(_)`. `.unavailable` is turned straight into the alert or a `.transientMessage` and back to `.idle`. Tapping the control while preparing or downloading gives up
- **Insertion rules** (`EntryDraft` + `DictationSpacing`, pure and tested): the insertion point is the end of the editor's selection (`TextEditor(text:selection:)`) when listening starts, as a character offset; with no selection (never focused), text appends. Each final is trimmed and spliced in there, with a space before it unless it follows whitespace, an opening bracket or curly quote, or the start, or begins with closing punctuation; and a space after it unless the next character is whitespace or closing punctuation, or the end. The point then moves past the words. Pending text is shown grey at the insertion point, never written to `body`
- **Editing is paused while listening:** the editor is swapped for a read-only view. Stop shows `.finishing` (spinner), waits up to `DictationRule.finishTimeout` (2 s) for the last finals, drops anything still unconfirmed, and returns to the editor with the cursor after the inserted text
- **Save while listening** stops, waits the same way, then saves if the draft is valid (Save is enabled while listening when there's a topic and pending words). **Cancel while listening** drops the pending tail at once; inserted finals are already in the draft, so the usual discard prompt applies. Dictation state never makes a draft dirty; inserted finals do
- VoiceOver: the mic is "Dictate"; starting announces "Listening", ending announces "Dictation stopped"; volatile updates aren't announced

### Formatting and links

- **Markdown in the existing `body`**, no schema change. The subset: `**bold**`, `*italic*`, bulleted lists (lines starting `- ` or `* `), `[text](url)`, and bare `http(s)://` URLs. Everything else (headings, numbered lists, quotes, code, strikethrough, underscore emphasis, HTML, entities) shows as literal text. Nothing is ever dropped: a block that fails to parse shows its literal text
- **`MarkdownBody`** (pure, `nonisolated`): `blocks(_:)` splits paragraphs (runs of non-bullet lines, inner blank lines kept, so a plain entry is one paragraph and renders exactly as before) and bullet lists; `inline(_:)` uses `AttributedString(markdown:)` with **inline-only, whitespace-preserving** parsing, after backslash-escaping `` ` `` `~` `_` `<` `&` so unsupported syntax stays literal, then keeps only bold and italic intents. **Apple's parser autolinks bare URLs and email addresses itself**; autolinked emails are unlinked (only bare http(s) URLs link), an `NSDataDetector` pass links any http(s) URL the parser missed, and links outside `http` / `https` / `mailto` are removed. `links(in:)` gives unique http(s) URLs in reading order. `plainText(_:)` is the plain projection (link text kept, bullets one per line) behind `SearchableText.plain`; entries with no `*`, `[`, `]`, `\`, or bullet lines skip parsing
- **Where it's rendered:** entry detail uses `FormattedBody` (paragraphs as `Text(AttributedString)`, bullets as `•` rows with a hanging indent, `lineSpacing(3)`); link taps go through `openURL` (Safari). Timeline rows (`EntryRow`), Trash rows, search snippets, and search matching use `SearchableText.plain`. The composer, including its read-only dictation view, shows the raw Markdown
- **Formatting bar** (`ToolbarItemGroup(placement: .keyboard)` in the composer): Bold, Italic, Bullet List, Link. The operations are pure functions in `MarkdownEditing` on `(text, selection)` as character offsets, applied through the editor's `textSelection`:
  - Bold / Italic wrap the selection (edge whitespace stays outside), unwrap when the markers are just outside or selected, and insert a pair with the cursor between when nothing is selected. Asterisk runs decide which markers are whose: bold in runs of 2 or 3, italic in runs of 1 or 3, so `***both***` toggles either
  - Bullet List toggles `- ` on every touched line: removed if all are bullets, otherwise added to the ones missing it; blank lines are skipped across several lines; a selection ending at a line start doesn't touch that line
  - **Return** continues a list: `.onChange(of: draft.body)` passes old and new text to `continueList(from:to:)`, which acts only when exactly one newline was inserted into a bullet line — the new line gets `- `; on an empty bullet the bullet is removed and the list ends. Skipped while dictating. **Cursor placement after this rewrite isn't verified on a device** `[NEEDS VERIFICATION]`
  - **Link** opens `LinkSheet` (URL and text fields) and inserts `[text](url)` over the selection captured when it opened; empty text uses the URL. A clipboard URL is offered with `PasteButton` when `UIPasteboard.hasURLs` — **not read automatically**, because a programmatic read shows the system paste-permission prompt. With nothing selected, the text is filled with the page title (`title(for:)`, debounced) unless typed in; offline it stays empty. `LinkInput.url(from:)` accepts http, https, and mailto, adding `https://` to a bare host
  - Formatting changes the body, so it makes the draft dirty like typing
- **`LinkMetadataService`** (main-actor protocol, injected through `linkMetadataService`; one app-wide instance): `metadata(for:)` and `title(for:)`. `CachedLinkMetadataService` is the real one: **one `LPMetadataProvider` per fetch** (single-use), started on the main actor, 10 s timeout (`LinkPreviewRule.timeout`). Its completion handler runs on a background queue and **the fetched image files are deleted when it returns**, so it archives the metadata right there (`NSKeyedArchiver`, secure coding) and is built in a `nonisolated` helper so it isn't main-actor isolated. Archives go to `Caches/LinkMetadata/<FNV-1a hash>.archive`, with an in-memory copy; a missing file (evicted) is fetched again; a URL that failed isn't fetched again in the same session. Not synced, not in SwiftData. `FakeLinkMetadataService` (titles by URL, delay) is used by tests, previews, shell mode, and the hosted test run. The iOS 26.4 `LinkMetadata` type isn't used (the deployment target is iOS 26)
- **Previews** (`LinkPreviews`): in entry detail below the body and photos, above the map; one per unique http(s) link in reading order, at most 3 (`LinkPreviewRule.maximumPerEntry`). Each fetches in a `.task` when its page is on screen, never in timelines or search. Loaded: `LPLinkView` in a `UIViewRepresentable` sized through `sizeThatFits` (it opens the link itself when tapped; **not verified on a device**). Loading, offline, or failed: a compact row (globe, host, URL) that opens the link

### Clean Up

- **Button only, never automatic** — not after dictation, not on save. The composer's Clean Up button (`wand.and.sparkles`) sits left of the mic; it is **absent** unless `TextCleaner.availability` is `.available` (read when the sheet appears) and disabled when the body is empty or dictation isn't idle
- **On-device only:** `SystemLanguageModel.default`; no Private Cloud Compute, no other model, no network
- **`TextCleaner`** (protocol, injected through `textCleaner`): `availability`, `clean(_:)` for one chunk, and `prewarm()`. `FoundationModelsCleaner` is the real one: a **fresh `LanguageModelSession` per chunk** with fixed instructions (`FoundationModelsCleaner.instructions` — tune them there), `GenerationOptions(samplingMode: .greedy)`. Availability reasons are read defensively with `@unknown default` and mapped to device not eligible, Apple Intelligence off, model downloading, or other, and logged. Errors are classified from iOS 26's `LanguageModelSession.GenerationError` and iOS 27's `LanguageModelError`: context overflow, refused (guardrail, refusal, unsupported language), or failed. On iOS 26.4+ a chunk over 1,000 tokens (`tokenCount(for:)`) is treated as an overflow before it is sent. `FakeTextCleaner` (scripted transform, availability, delay) is used by tests, previews, shell mode, and the hosted test run
- **Prewarm** once per composer, only when Clean Up is likely: when dictation ends, or once the body passes 280 characters (`CleanUpRule.prewarmLength`)
- **Chunking** (`CleanUpChunks`, pure): one chunk per paragraph or bullet list — runs of non-blank lines, split at blank lines and where bullets start or stop. Separators are the exact original text between chunks, so joining every piece reproduces the body exactly. A chunk over the budget (3,000 characters ≈ 1,000 tokens) splits at sentence boundaries (`enumerateSubstrings(options: .bySentences)`, ICU — which doesn't break before a lowercase word, so uncapitalized dictation falls through to the next rule), packing sentences up to the budget; one sentence over it splits at spaces. Chunks are cleaned in order
- **Errors** (`CleanUpRunner`): a context overflow re-splits that chunk at half the size **once**, then gives up; refused or failed keeps the chunk unchanged. Any failure leaves only that chunk original
- **Safety post-check** (`CleanUpCheck`, pure) before accepting a cleaned chunk: not empty; length 50–130% of the original; every link destination identical and in the same order (I11a parsing); the same number of `*`, `[`, and `]`; the same number of bullet lines. Anything failing keeps the original chunk
- **Composer:** while cleaning, the editor is read-only and the button becomes a "Cleaning up…" capsule; tapping it, or the sheet's Cancel, stops and keeps the original; Save is disabled. When done the body is replaced in one step and the button becomes **Revert** (`arrow.uturn.backward`), which restores the original exactly, until the next edit (no partial revert), Save, or Cancel. Nothing changed (or every chunk rejected) → "No changes"; some chunks failed → "Some text couldn’t be cleaned up". Clean Up changes `body`, so the draft becomes dirty; Revert restores the previous dirty state. VoiceOver hears "Cleaned up" / "Reverted". The state lives on the draft (`EntryDraft.CleanUpState`: `beginCleanUp`, `finishCleanUp`, `cancelCleanUp`, `revertCleanUp`, `bodyDidChange`) and never makes it dirty by itself
- The original is never stored after Save (no schema change). **Real model output is unverified until tried on a device with Apple Intelligence** `[NEEDS VERIFICATION]`

### Search

- **Lives on the topics list only** (the bottom-toolbar `.searchable` field). With 2+ characters (`SearchQuery.minimumLength`, ignoring surrounding whitespace) `SearchResultsView` replaces the topic sections; fewer shows the normal list. Debounced 250 ms (`SearchRule.debounce`) in a `.task(id:)` keyed on the text and the navigation depth, so typing cancels a pending search (no stale results) and returning from a result reruns it (edits, moves, and trashing show)
- **Scope:** entry text, entry place name, and topic titles. Not photos, dates, or topic summaries. **Live entries only** (`Entry.isLive`); archived topics and their entries are included and marked "Archived". Trashed topics never match
- **Matching** (`SearchQuery`): the query is split on whitespace, each word trimmed of surrounding punctuation and symbols, and punctuation-only words dropped. **Every word must match**, in any order, in the text or the place name (one word can match each). Case- and diacritic-insensitive via `localizedStandardContains` ("cafe" finds "Café"). No fuzzy matching; a straight apostrophe doesn't match a curly one
- **Searchable plain text:** matching and snippets read the body only through `SearchableText.plain(_:)`, which returns the Markdown plain projection (`MarkdownBody.plainText`), so formatting characters are ignored. The store-side first-word narrowing still runs on the raw body; a word is only missed there if markup splits it (`b**ol**d`)
- **Order and cap** (`SearchResults`): topics by recent activity, then entries newest first by `date` (ties by `createdAt`), at most 100 (`SearchResults.entryLimit`) with a "Showing the 100 most recent matches" footer
- **Fetching** (`EntrySearch`): live topics are fetched whole; entries are narrowed in the store by the **first** word, `deletedAt == nil && (body.localizedStandardContains(word) || placeName?.localizedStandardContains(word) == true)`, then `SearchResults` applies `isLive`, every word, order, and the cap in memory. It runs on the main context after the debounce. **SwiftData predicate finding** (iOS 27 simulator): `localizedStandardContains` is supported, including diacritic-insensitive matching, but `(placeName ?? "").localizedStandardContains(…)` throws an Objective-C exception at fetch time that crashes the app; optional chaining compared with `== true` works. `SearchFetchTests` runs this predicate against a seeded store
- **Snippets** (`SearchSnippet`): one line of text (whitespace runs collapsed), from up to 40 characters before the first match (starting at a word, "…" when cut) to about 140 characters (ending at a word, "…" when cut), with every match range for bold highlighting. When the match is only in the place name the snippet is the start of the text; the place name is shown, highlighted, whenever a word matches it
- **Opening a result pushes the topic and then the entry** onto the path (`path.append(topic)`, `path.append(entry)`); a topic result pushes the topic. Back from the entry goes to the topic, and Back again to the results with the query intact. Result rows check `isAvailable` before reading their model
- Rows read "Topic, date, [Archived,] snippet[, place]" to VoiceOver; the result counts are announced when they change after the debounce. Empty results show `ContentUnavailableView.search(text:)`

### App lock

- **Optional, off by default, per device.** Settings live in `UserDefaults` under `AppLock.enabledKey` (`appLock.isEnabled`), `AppLock.promptedKey` (`appLock.hasPrompted`), and `AppLock.turnedOffKey` (`appLock.turnedOffUnavailable`); never synced. `AppLock` reads and writes them directly (not `@AppStorage`) so tests can inject a suite
- **`BiometricAuthenticator`** (protocol): `canAuthenticate()` → `.available(BiometryKind)`, `.passcodeNotSet`, or `.unavailable`; `authenticate(reason:)` → `.success`, `.cancelled`, `.failed`, `.unavailable`. `LocalAuthenticator` is the real one: `LAContext` with **`.deviceOwnerAuthentication`** (Face ID / Touch ID, falling back to the passcode), a **fresh context per check and attempt**, and the async `evaluatePolicy(_:localizedReason:)`. The biometry kind comes from a second `canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` check, because `biometryType` is only filled in by a biometric policy; no biometry enrolled → "Passcode" wording. Cancel, system/app cancel, fallback, and not-interactive map to `.cancelled`; `passcodeNotSet` to `.unavailable`; anything else to `.failed`. `FakeBiometricAuthenticator` (fixed availability and result) is used by tests and previews; tests and shell mode get an `AppLock` with an unavailable fake and its own defaults suite, so it never engages
- **`AppLock`** (`@Observable`, main actor; owned by `CommonplaceApp`, in the environment; injected clock `now`). Rules, all unit-tested:
  - cold launch + enabled → locked (set in `init`, before the first frame)
  - `.inactive` + enabled → obscured (privacy cover); `.background` → record `backgroundedAt`, stay obscured
  - `.active` + enabled → locked if `backgroundedAt` is at least 60 s ago (`AppLock.gracePeriod`), otherwise just uncovered. **Inactive → active without a background (Control Center, a system prompt) never locks**; this reads the brief's "or no timestamp" as the cold-launch case, since locking there would loop on the Face ID prompt itself
  - scene changes during an authentication are ignored (the system prompt makes the scene inactive)
  - success → unlocked and uncovered; cancelled or failed → stays locked with the Unlock button
  - disabled → never locked or obscured
  - the lock screen authenticates automatically **once per lock** (`lockCount`), and only while the scene is active
- **Turning it on or off** (the one-time offer's Turn On, and the Settings toggle in both directions) authenticates first; only success changes the setting. The offer is shown once, after the first frame, as an alert over the topics list, when not yet answered, the lock is off, and the device can authenticate; answering either way sets `hasPrompted`. Turning it on doesn't lock the current session
- **Losing the ability to authenticate** (passcode removed), noticed at launch, on each return to `.active`, or from an attempt: the app unlocks, the setting turns off, and `wasTurnedOffUnavailable` makes Settings explain why
- **Covering everything — never dismiss presented UI on lock.** Sheets, covers, alerts, pickers, and drafts stay as they are; the cover goes on top. `.appLock(_:)` (`Screens/LockScreen.swift`) adds both: a SwiftUI `.overlay` on the root view, which covers the first frame on a cold launch, and an **overlay window** — a second `UIWindow` on the scene at `.alert + 1`, hosting `LockScreen` in a `UIHostingController`, made key while covering (VoiceOver gets a screen-changed notification and the view is modal) and hidden after, with the previous key window made key again. A root-view overlay alone doesn't reach sheets or full-screen covers presented above it. **Not yet verified on a simulator or device** `[NEEDS VERIFICATION]`: that the window covers sheets, `fullScreenCover`, `PhotosPicker`, alerts, and the keyboard, that VoiceOver focus moves in and back, and that the keyboard returns after unlocking. Record the findings here
- Settings: "Require Face ID" (per biometry) above Trash retention, disabled with an explanatory footer when the device can't authenticate. The composer already stops dictation when the scene leaves `.active` (I8)

### Location

- **`LocationService`** (protocol, injected through the `locationService` environment value) gives a one-shot fix and a place name. `CoreLocationService` is the real one; `FakeLocationService` (fixed coordinate, configurable delay, denied / unavailable, offline geocoding) is used by tests, previews, shell mode, and the hosted test run. `.sampleData()` injects the fake, so previews never ask for access or geocode
- **APIs chosen:** the fix uses `CLLocationUpdate.liveUpdates()` with `CLServiceSession(authorization: .whenInUse)` — `Sendable` async APIs with no delegate to bridge. The place name uses MapKit's `MKReverseGeocodingRequest`; **`CLGeocoder` is deprecated in iOS 26, don't use it**. Maps opens through `MKMapItem(location:address:)`; `MKPlacemark` is deprecated too
- **When In Use only.** No background location, no `allowsBackgroundLocationUpdates`, no region or significant-change monitoring. Permission is asked at first need — the first time a composer opens with location on — never at launch. The topic editor's toggle is only a preference and asks for nothing
- **Capture rules** (`LocationCaptureRule`): capture starts when the composer opens, not on Save. Take the first fix accurate to 100 m, otherwise the best fix within 15 s; a reduced-accuracy (approximate) fix is accepted as-is. Time spent on the permission prompt doesn't count against the 15 s
- **`EntryDraft` location state:** `capturesLocation` starts from the topic's setting for a new entry and from `entry.hasLocation` for an edit. In the from-list composer it follows the picked topic (`setTopic(_:)`) until the user chooses by hand. `applyLocation(to:)` clears all three fields when location is off, sets them when a fix was captured in the sheet, and otherwise leaves the entry alone — so an edit never loses a location it didn't deliberately replace, and back-dating never touches it. `apply(to:)` and `applyPhotos(to:in:)` never touch location
- **Dirty rules:** choosing to include or remove location is dirty, and so is a fix captured while editing. A fix captured automatically for a new entry is not
- **Saving doesn't wait for a fix.** `LocationCapture` (app-level, in the `locationCapture` environment value) takes over when the sheet closes: `startLateFix(for:timeout:)` keeps locating for the rest of the 15 s and attaches the coordinates only if the entry still has none and isn't trashed. A late fix therefore never replaces an edited entry's existing location
- **Place-name rule** (`PlaceCandidate.placeName`): the point of interest's name when the result is one; otherwise the city with its state or province ("Sedona, AZ", MapKit's `cityWithContext(.short)`); otherwise the city alone; otherwise `nil`, and the entry shows formatted coordinates (`LocationLabel`)
- **Backfill:** entries saved with coordinates and no place name (offline) are named later by `LocationCapture.backfillPlaceNames()`, run from `RootView` on launch and each return to the foreground. It works serially, five per run, and stops at the first failed lookup. No timers or polling
- **Entry detail** shows `EntryLocationView` below the photos when `entry.hasLocation`: a non-interactive `Map` with a pin in the topic's color, and a place line that is always visible so the location is usable when map tiles aren't available. Tapping it opens Apple Maps through `MapsApp.open(_:name:)` (`MKMapItem(location:address:)`), which the topic map's card reuses

### Topic map

- **Entry points:** a Map button (`map`) in topic detail's top toolbar beside •••, and "Show Map" in the ••• menu; both are `NavigationLink(value: AppRoute.topicMap(topic))` and appear only when `TopicMapModel.locatedEntries(for:)` isn't empty. `RootView` maps the route to `TopicMapView`, which is pushed (Back returns to the topic). Archived topics have a map too. "Show Map" is a `NavigationLink` inside a `Menu`; verified on a device that it pushes the map
- **What it shows** (`TopicMapModel`, pure and tested): `locatedEntries(for:)` — live (`isLive`) entries with both coordinates, newest first. The bottom caption is `caption(located:total:)` ("12 of 23 entries have a location") over every live entry. Live updates come through the `Topic.entries` relationship like the timeline: trashing, moving (I7b), or removing a location takes the pin off and closes its card; with none left the screen shows "No Entries with a Location"
- **Camera:** opened on `fittingRegion(for:)` — the pins' bounding box × 1.4, at least 1 km across (`minimumSpanMeters`), so a single pin gets about 1 km. The antimeridian is ignored (points either side span the world the long way)
- **Clustering finding (iOS 27 SDK):** SwiftUI `Map` (`_MapKit_SwiftUI`) has **no native annotation clustering** — nothing in its interface mentions clustering; only `MKMapView` has it. So grouping is custom and stays in SwiftUI: `TopicMapModel.groups(_:region:mapWidth:)` merges pins closer than 44 pt on screen, measured in Web Mercator world space (so panning never regroups, only zooming), greedily around each group's first pin; centroid = mean of members. It's recomputed from `onMapCameraChange(frequency: .onEnd)` and the map's width. At 300 m wide or less (`ungroupedWidthMeters`) nothing groups, and tapping a bubble fits its members at least 200 m across (`groupZoomSpanMeters`), so a tap always splits it — even entries at the same spot
- **Pins:** `Marker` per entry, tinted with the topic color, tagged with its `PersistentIdentifier` for `Map(position:selection:)`. Titles are hidden (`.annotationTitles(.hidden)`) to avoid clutter; the title carries the VoiceOver label ("Oct 2, 6:10 AM, Cathedral Rock", `EntryTimeline.dateAndTime`). Verified on a device that VoiceOver reads the hidden title. Group bubbles are `Annotation`s with a button ("5 entries near Cathedral Rock, zoom in")
- **Preview card** (bottom safe-area inset, replacing the caption while a pin is selected): dot + date and time, place (`LocationLabel.text`), first line of plain text (`firstLine(of:)`), first thumbnail; tapping it pushes the `Entry` (entry detail's chip and Back return to the map, then the topic), and Open in Maps uses `MapsApp`. Selecting recenters the pin at the current zoom above the card and moves VoiceOver focus to the card; tapping the map elsewhere clears the selection. Camera moves and the card's slide skip animation with Reduce Motion
- **Map style:** Standard / Hybrid / Satellite (`.imagery`) from the toolbar menu, a per-device preference in `@AppStorage(TopicMapStyle.storageKey)` (`topicMapStyle`), stored as the raw value; unknown values fall back to Standard
- **No permission prompt from the map, ever.** `LocationService.isAuthorized` only reads the status (`CLLocationManager().authorizationStatus`); `UserAnnotation` and `MapUserLocationButton` appear only when it's already granted. `FakeLocationService.isAuthorized` is `false` by default
- **Offline:** pins, groups, and cards come from SwiftData, so they work without tiles
- Model files still import only Foundation; `Coordinate` lives in `Persistence/LocationService.swift`

### Entry detail

- **Entry detail is a reader for the whole topic, and paging happens in place.** The navigation stack keeps the `Entry` that was tapped; swiping or tapping a neighbor changes which entry is shown (`current`) without pushing. Back and the topic chip always return to the topic
- The toolbar, the ••• menu (Edit, and Move to Trash / Delete Permanently when wired), the neighbor bar, and the photo viewer all act on `current`, never on the tapped `entry`
- **Reading order** is `EntryTimeline.readingOrder`: oldest → newest by `date`, ties by `createdAt`, over the topic's `liveEntries`. Older is on the left. `neighbors(of:in:)` is built on it, and it is the reverse of the timeline's order. No wrap-around
- Pages are a horizontal `ScrollView` + `LazyHStack` with `.scrollTargetBehavior(.paging)` and a `ScrollPosition` created with `idType: PersistentIdentifier.self`
- **Only a scroll moves the reader.** `current` is updated from the scroll position while a scroll is in progress or settles. When the entry list changes underneath (a re-dated edit, an import, a trashed entry), `keepPlace()` scrolls back to `current` without animation; if `current` is no longer live it moves to `EntryTimeline.replacement(for:in:)` (newer neighbor, else older), or pops to the topic when none remain. Trashing or deleting the current entry from the ••• menu takes the same path
- Neighbor buttons are the accessible way to page; a page change posts an accessibility announcement of the position ("3 of 6"), and the animated scroll is skipped with Reduce Motion
- The topic chip uses `dismiss()`, which is right because entry detail is always pushed on top of its topic or that topic's map: search results push the topic and then the entry (see Search), and from the topic map the chip returns to the map
- **Back gesture vs. paging — not yet verified on a device.** iOS 26 added a content-area back swipe in navigation stacks, which can compete with horizontal paging. Required: a mid-topic horizontal swipe pages, and the leading-edge back gesture still pops. Only supported SwiftUI APIs are used and the system back gesture is not disabled. Record the observed behavior here once checked

### Routes (GPX)

- **One route per entry, attached from that entry only.** Entry detail's ••• menu has **Add Route…** (or **Replace Route…** / **Remove Route** when it has one), acting on `current`. No import in topic detail, no batch import, no matching files to entries. Routes are drawn on the entry detail map and the Route view only — **never on the topic map (I13)**
- **GPX type:** `UTType.gpx` is `com.topografix.gpx` (declared under Target → Info → Imported Type Identifiers: conforms to `public.xml`, extension `gpx`, MIME `application/gpx+xml`). Without that declaration it falls back to `UTType(filenameExtension: "gpx", conformingTo: .xml)`. The declaration is in `Commonplace/Info.plist` (`UTImportedTypeDeclarations`). **Whether `.gpx` files are selectable in the Files picker is not yet verified on a device** `[NEEDS VERIFICATION]`
- **Import flow:** `.fileImporter` (one file) → `RouteFile.read` (security-scoped, off the main actor, files over 10 MB refused before reading) → `RouteImporter.makeRoute(from:fileName:)` (`GPXRouteImporter`, `@concurrent`: parses and computes off the main actor into a `Sendable` `RouteDraft`) → `RouteAttachSheet` → Save → `RouteOperations.attach` (one `saveOrRollback()`). Cancel saves nothing. Errors show "Couldn’t Add Route" with `GPXError.message` (`.routeErrorAlert(_:)`). `FakeRouteImporter` is for previews; the real importer has no device dependencies, so the app and tests use it
- **Confirm sheet:** name, recorded date, stats, a still map of the line; a quiet footer when the track's day differs from the entry's ("Recorded Oct 14 · entry dated Oct 15", `RouteAttachText.dateNote`); and **Use route start as entry location** (off by default) only when the entry has no location. That sets the coordinates with no place name, and the I6 backfill names it (run right after the save too). **An existing location is never replaced**
- **Replace** confirms before the picker; the old `Route` is deleted when the new one is saved. **Remove** confirms, then deletes the `Route` outright — **a hard delete, like removing a photo; no Trash.** Trashing an entry keeps its route; restoring shows it; a permanent delete or purge cascades (`Entry.route` is `.cascade`)
- **`GPXParser`** (pure, `XMLParser`, namespaces processed so prefixes don't matter): every `<trk>/<trkseg>/<trkpt>` in order, one segment per `<trkseg>`; with no track points, `<rte>/<rtept>` as one segment. `<wpt>`, extensions, and unknown elements are ignored. The name is the first non-empty `<trk><name>` (CDATA included), else `<rte><name>`, else the file name without its extension (`RouteDraft.name`), else "Route". Times are ISO 8601 with or without fractional seconds. Typed errors: `tooLarge` (> 10 MB), `notGPX` (not XML, or the root isn't `<gpx>`), `noTrack` (< 2 points), `tooManyPoints` (> 50,000) — limits in `RouteLimits`
- **`RouteMetrics`** (pure, tested; no MapKit types): **distance** is the haversine sum (R = 6,371,000 m) between consecutive points within each segment, **not across segment gaps**. **Elevation gain** uses a **5 m hysteresis** over all elevations in order (points without `<ele>` skipped): `ref` = first; a rise of ≥ 5 m adds the rise and moves `ref`; a fall of ≥ 5 m moves `ref`; `nil` with no elevations. Min / max elevation, first / last timestamp (Time = last − first; no moving time, pace, or calories), start coordinate. Michael's Broken Arrow export: 3.00 mi, 125 m / 411 ft gain (771 ft raw), 96 min
- **Cached drawing data:** `pathData` is Douglas–Peucker per segment at 5 m on a local equirectangular projection, the tolerance doubled until ≤ 2,000 points; segments stay separate so gaps aren't drawn. `RoutePath` encodes `[[lat, lon]]` per segment; `profileData` is `RouteProfile`, 200 samples of `[distance m, elevation m]` evenly spaced by distance from 0 to the full distance (interpolated; omitted with no elevations). Both are binary property lists, inline. **Display reads only these, decoded off the main actor (`RoutePathDecoder`) in a `.task` — never the GPX file.** Paging is lazy, so only visible pages decode
- **Entry detail map** (`EntryLocationView`): with a route it draws `MapPolyline`s in the topic color (4 pt), keeps the pin, fits the camera to the route plus the pin with an explicit region (`RouteCamera.region`, built on `TopicMapModel.fittingRegion`, min 500 m), and shows `RouteStatsRow` (Distance · Elev. gain · Time; gain and time omitted when unknown) under the place line. **Tapping it pushes the Route view** (`AppRoute.route(entry)`); without a route it opens Apple Maps exactly as in I6. A route with no location still shows the map, without a pin. VoiceOver: "Location: …. Route, 3.0 miles, 397 feet gain. Opens route."
- **Route view** (`RouteView`, pushed): interactive `Map` with the polyline, a Start marker, and the entry pin; a bottom panel with the name, recorded date, stats, the elevation profile (Swift Charts area + line, locale units, `accessibilityChartDescriptor` summary "Elevation from 4,282 to 4,631 feet"), and **Open in Maps** for the entry's location (hidden without one; Apple Maps can't show the track). User location only when already authorized
- **Units** (`RouteStats`, tested): miles and feet in the US; miles and meters in the UK; kilometers and meters elsewhere, via `Measurement` formatting. Time is `1h 36m` (spoken "1 hour, 36 minutes")
- **Timeline row:** `EntryRow` shows the route glyph (`RouteSymbol.name`, `point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath`, SF Symbols 2024) after the time when the entry has a route
- **Seed:** Cathedral Rock (out-and-back) and Airport Mesa (loop) have synthetic routes; a Dolly Sods entry ("Hiked out to Bear Rocks") has a two-segment route and no location. `SampleRoutes` generates the tracks and their GPX; no recorded track ships in the app

### Shell mode — off

`AppConfig.usesSampleData` is `false` since I2: the app runs on `ModelContainerFactory.makePersistent()` with the real clock (`referenceDate` is `nil`). The switch is kept so the shell can be turned back on for design work; when `true`, the app runs on a seeded in-memory container (`SampleData.makeContainer()`) and nothing persists.

- The seed now exists for previews (and the switch). `SampleData.seed(into:)` has a `precondition` that the container is in-memory with CloudKit disabled. Sample data must never reach the persistent container
- Parts of the app that are still inert must not call `modelContext.insert` / `delete` / `save`. Still inert after I11b: the photo viewer's Share button
- Seed dates are fixed (September–October 2026) around `SampleData.now`, which previews pass as `referenceDate`
- Seed photos are generated at seed time (`PlaceholderImage`); no image files are bundled or downloaded

### Previews

Every `#Preview` uses the seeded container through `.sampleData()` (defined beside `PreviewContainer`), which attaches `PreviewContainer.shared` and the seed's `referenceDate`. The one exception is `RootView`'s "Empty" preview, which uses an unseeded in-memory container to show the fresh-install state. Fetch preview models with `PreviewContainer.topic(_:)` and `PreviewContainer.entry(in:at:)`. Each screen has light and dark previews.

## Data model

Models are defined inside `SchemaV2` (a `VersionedSchema`, version `2.0.0`) and exposed through top-level typealiases (`Topic`, `Entry`, `Photo`, `Route`). App code never refers to the version namespace.

`SchemaV1` (`1.0.0`) is **frozen**: its own copies of `Topic`, `Entry`, and `Photo` with only the stored properties, relationships, and an init, exactly as V1 shipped. Only the migration test uses it. Never change it.

### Route (V2, I16)

- `Route`: `gpxData: Data?` (`.externalStorage`, synced as a CloudKit asset — the original file, so stats can be recomputed), `name`, `startedAt?`, `endedAt?`, `distanceMeters`, `elevationGainMeters?`, `minElevationMeters?`, `maxElevationMeters?`, `startLatitude?`, `startLongitude?`, `pathData?`, `profileData?` (inline, small), `createdAt`, and `entry` (the inverse side)
- `Entry.route: Route?` — `@Relationship(deleteRule: .cascade, inverse: \Route.entry)`; `Entry.hasRoute`
- **CloudKit Production needs a schema deploy for V2.** Run a debug build against the Development environment and add a route so `CD_Route` (with `CD_gpxData` as an asset) and `CD_Entry.CD_route` exist, then CloudKit Console → Deploy Schema Changes, **before** a build with V2 reaches a device with real data

### Location fields

Added in I2 so the schema was settled before real data accumulated; used since I6 (see UI → Location).

- `Topic.capturesLocation: Bool = false` — whether new entries in the topic capture location by default
- `Entry.latitude: Double?`, `Entry.longitude: Double?`, `Entry.placeName: String?` — all `nil` by default
- **Both coordinates or none.** `Entry.hasLocation` is true only when `latitude` and `longitude` are both set; always set and clear them together
- `placeName` can be `nil` while a location exists (captured offline, geocoded later)
- Model files stay Foundation-only: no `CoreLocation` import there

### CloudKit model rules

These apply to every model change:

- Every stored property has a **default value at its declaration** (not only in `init`) or is optional
- All relationships are **optional**
- **No** `@Attribute(.unique)`, **no** `#Unique`
- A relationship's inverse is declared on **one** side only
- Enums are stored as their `String` raw value, not as the enum type

### Schema changes are additive only

Once the schema is deployed to the CloudKit production environment, only additive changes are possible: new optional or defaulted properties and new models. Renames, type changes, and removals are not.

### Migration plan — deliberately deferred

**No `SchemaMigrationPlan` is created or passed to `ModelContainer`**, even with `SchemaV2`. There are reports of `ModelContainer` failing to load when CloudKit is enabled and a migration plan is passed. V1 → V2 is additive (a new model and an optional relationship), and SwiftData's automatic lightweight migration handles it: **verified (iOS 27 simulator, I16)** by `SchemaMigrationTests`, which writes an on-disk store with `SchemaV1`, closes it, and reopens it with `SchemaV2` and no plan — data intact, `route == nil`, and a new `Route` saves. Do not add a plan reflexively. Add one only if a later schema needs a non-additive step, and verify against the then-current SwiftData behavior first

### Soft delete and Trash

- **Move to Trash is the default delete everywhere**: it sets `deletedAt`, needs no confirmation, and syncs like any edit. There is no undo toast; Trash is the undo
- **All of it goes through `TrashOperations`** (`Persistence/TrashOperations.swift`): `moveToTrash`, `restore`, `deletePermanently`, `emptyTrash`, `purge(retention:)`, and the counts used in confirmation copy. Each operation ends in `saveOrRollback()` and returns the error message for `.saveErrorAlert(_:)`
- **`modelContext.delete` is called only in `TrashOperations`** (permanent delete, Empty Trash, purge), in `EntryDraft.applyPhotos` (removing a photo from an entry; see Photos), and in `RouteOperations` (removing or replacing a route; see Routes). Nowhere else. Cascades (topic → entries → photos and route) fire only then
- **Every permanent delete is confirmed** with accurate counts. A topic's count is every entry the delete removes, including ones already in Trash (`TrashOperations.entriesDeleted(with:)`). Entries share one alert, `.deleteEntryAlert(_:delete:)`
- **Trashing a topic stamps only the topic.** Its entries keep their own `deletedAt`. Restoring the topic brings back the entries that were live, not ones trashed individually, and keeps its archived state
- **Restoring an entry whose topic is in Trash restores the topic too**, after a confirmation that names it ("Restore Both"). `TrashOperations.restore(_ entry:)` does both; the view asks first
- **Live means live all the way up.** An entry is shown outside Trash only if it isn't trashed and its topic isn't trashed: `Entry.isLive`. `Topic.liveEntries` is the narrower "not individually trashed" list a topic shows and brings back when restored. Topic lists query `deletedAt == nil`. **Search filters with `Entry.isLive`**
- **Retention** (`TrashRetention`: 30 days by default, 90 days, or Never) is a per-device preference in `@AppStorage(TrashRetention.storageKey)`, not synced, so in practice the shortest setting among devices wins. Shortening it asks first when that would delete items now
- **Auto-purge** runs from `RootView` when the app becomes active, at most once a day (`TrashRetention.lastPurgeKey`), and deletes items trashed at or before `cutoff(before:)`. Failures are logged, not shown
- **The clock is injected:** `TrashOperations.now` is a closure, replaced in tests to control time
- **After a permanent delete, a view can outlive its model for a moment, and reading a deleted model's properties traps.** Screens and rows that take a model check `isAvailable` first (`TopicDetailView`, `EntryPage`, `EntryRow`), and entry detail works out the replacement entry before deleting the current one

## Containers

`ModelContainerFactory` produces both stores:

- `makePersistent()` — the CloudKit-backed store. Only the running app calls it
- `makeInMemory()` — in-memory, CloudKit disabled. **Tests and previews always use this one** (and shell mode, when switched on)

Unit tests are hosted in the app, so the app launches during `make test`. `CommonplaceApp` detects a test run (the `XCTestConfigurationFilePath` environment variable) and uses an empty, unseeded in-memory container, so the CloudKit store is never created from tests. `ModelContainerFactoryTests` guards that the variable is set.

No sample or seed data is ever inserted into the persistent container.
