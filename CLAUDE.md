# Commonplace

iOS app (iPhone only, iOS 26+): a personal structured journal. SwiftUI + SwiftData, synced through the private CloudKit database `iCloud.com.aurlaw.commonplace`.

Phase briefs live in the Tech Obsidian vault under `commonplace/phases/`.

## Layout

- `Commonplace.xcodeproj` — Xcode project. **Never edit it** (including `project.pbxproj`)
- `Commonplace/` — app sources
  - `Models/` — `SchemaV1` models and `TopicColor` (Foundation only, no SwiftUI)
  - `Persistence/` — `ModelContainerFactory`, `ModelContext.saveOrRollback()`, `LastUsedTopic`, `ImageProcessor` (with `PhotoLimits` and `ImageDownsampler`), `LocationService`, and `LocationCapture`
  - `DesignSystem/` — shared components (`TopicRow`, `EntryRow`, `TopicHeader`, `TopicChip`, `ThumbnailStrip`, `PhotoGrid`) and the pure `EntryTimeline` helpers
  - `Screens/` — one file per screen or sheet; `RootView` owns the navigation stack
  - `SampleData/` — the seed, placeholder images, `PreviewContainer`, and `FakeLocationService`
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

No third-party packages, including test helpers and formatters. Apple frameworks only: SwiftUI, SwiftData, PhotosUI, ImageIO, CoreImage, Speech, AVFoundation, CoreLocation, MapKit, LocalAuthentication.

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
- The topic can't be changed when editing. `EntryDraft.apply(to:)` writes the date and body only — never photos, location, topic, `createdAt`, or `deletedAt`
- Dictation state and its grey pending text are never written to the body
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
- **Photo hard-delete exception:** removing a photo in the composer calls `modelContext.delete(photo)` on Save, with no Trash and no confirmation. This is the one user-facing delete outside permanent delete and purge. Cancel discards the removal
- **Never show a full-size bitmap in a grid or strip.** Small tiles and strips use `thumbnailData` through `PhotoImage`. Anything larger uses `DownsampledPhotoImage`, which decodes `imageData` off the main actor at a stated pixel size and shows the thumbnail until it is ready (and whenever `imageData` is still `nil` after a sync). The viewer keeps a full-size bitmap for the visible page only

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
- **Entry detail** shows `EntryLocationView` below the photos when `entry.hasLocation`: a non-interactive `Map` with a pin in the topic's color, and a place line that is always visible so the location is usable when map tiles aren't available
- Model files still import only Foundation; `Coordinate` lives in `Persistence/LocationService.swift`

### Entry detail

- **Entry detail is a reader for the whole topic, and paging happens in place.** The navigation stack keeps the `Entry` that was tapped; swiping or tapping a neighbor changes which entry is shown (`current`) without pushing. Back and the topic chip always return to the topic
- The toolbar, the ••• menu (Edit, and Move to Trash / Delete Permanently when wired), the neighbor bar, and the photo viewer all act on `current`, never on the tapped `entry`
- **Reading order** is `EntryTimeline.readingOrder`: oldest → newest by `date`, ties by `createdAt`, over the topic's `liveEntries`. Older is on the left. `neighbors(of:in:)` is built on it, and it is the reverse of the timeline's order. No wrap-around
- Pages are a horizontal `ScrollView` + `LazyHStack` with `.scrollTargetBehavior(.paging)` and a `ScrollPosition` created with `idType: PersistentIdentifier.self`
- **Only a scroll moves the reader.** `current` is updated from the scroll position while a scroll is in progress or settles. When the entry list changes underneath (a re-dated edit, an import, a trashed entry), `keepPlace()` scrolls back to `current` without animation; if `current` is no longer live it moves to `EntryTimeline.replacement(for:in:)` (newer neighbor, else older), or pops to the topic when none remain
- Neighbor buttons are the accessible way to page; a page change posts an accessibility announcement of the position ("3 of 6"), and the animated scroll is skipped with Reduce Motion
- The topic chip uses `dismiss()`, which is right only while entry detail is pushed from a topic. Search results (I9) will push it from the topics list and must decide how the chip behaves there
- **Back gesture vs. paging — not yet verified on a device.** iOS 26 added a content-area back swipe in navigation stacks, which can compete with horizontal paging. Required: a mid-topic horizontal swipe pages, and the leading-edge back gesture still pops. Only supported SwiftUI APIs are used and the system back gesture is not disabled. Record the observed behavior here once checked

### Shell mode — off

`AppConfig.usesSampleData` is `false` since I2: the app runs on `ModelContainerFactory.makePersistent()` with the real clock (`referenceDate` is `nil`). The switch is kept so the shell can be turned back on for design work; when `true`, the app runs on a seeded in-memory container (`SampleData.makeContainer()`) and nothing persists.

- The seed now exists for previews (and the switch). `SampleData.seed(into:)` has a `precondition` that the container is in-memory with CloudKit disabled. Sample data must never reach the persistent container
- Parts of the app that are still inert must not call `modelContext.insert` / `delete` / `save`. Still inert after I6: Move to Trash, Delete Permanently, Trash actions, Settings retention, dictation (the button only toggles its visual state), search, and the photo viewer's Share button
- Seed dates are fixed (September–October 2026) around `SampleData.now`, which previews pass as `referenceDate`
- Seed photos are generated at seed time (`PlaceholderImage`); no image files are bundled or downloaded

### Previews

Every `#Preview` uses the seeded container through `.sampleData()` (defined beside `PreviewContainer`), which attaches `PreviewContainer.shared` and the seed's `referenceDate`. The one exception is `RootView`'s "Empty" preview, which uses an unseeded in-memory container to show the fresh-install state. Fetch preview models with `PreviewContainer.topic(_:)` and `PreviewContainer.entry(in:at:)`. Each screen has light and dark previews.

## Data model

Models are defined inside `SchemaV1` (a `VersionedSchema`, version `1.0.0`) and exposed through top-level typealiases (`Topic`, `Entry`, `Photo`). App code never refers to the version namespace.

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

`SchemaV1` is a `VersionedSchema`, but **no `SchemaMigrationPlan` is created or passed to `ModelContainer`**. With one schema version there is nothing to migrate, and there are reports of `ModelContainer` failing to load when CloudKit is enabled and a migration plan is passed. Do not add a plan reflexively. Add one only if a `SchemaV2` needs it, and verify against the then-current SwiftData behavior first.

### Soft delete

- User-facing deletes set `deletedAt`; they never call `modelContext.delete`. The one exception is removing a photo from an entry (see Photos)
- `modelContext.delete` is only for permanent delete and purge. Cascade rules fire only then
- Every user-facing query filters `deletedAt == nil`

## Containers

`ModelContainerFactory` produces both stores:

- `makePersistent()` — the CloudKit-backed store. Only the running app calls it
- `makeInMemory()` — in-memory, CloudKit disabled. **Tests and previews always use this one** (and shell mode, when switched on)

Unit tests are hosted in the app, so the app launches during `make test`. `CommonplaceApp` detects a test run (the `XCTestConfigurationFilePath` environment variable) and uses an empty, unseeded in-memory container, so the CloudKit store is never created from tests. `ModelContainerFactoryTests` guards that the variable is set.

No sample or seed data is ever inserted into the persistent container.
