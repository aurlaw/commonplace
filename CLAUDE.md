# Commonplace

iOS app (iPhone only, iOS 26+): a personal structured journal. SwiftUI + SwiftData, synced through the private CloudKit database `iCloud.com.aurlaw.commonplace`.

Phase briefs live in the Tech Obsidian vault under `commonplace/phases/`.

## Layout

- `Commonplace.xcodeproj` — Xcode project. **Never edit it** (including `project.pbxproj`)
- `Commonplace/` — app sources
  - `Models/` — `SchemaV1` models and `TopicColor` (Foundation only, no SwiftUI)
  - `Persistence/` — `ModelContainerFactory`
  - `DesignSystem/` — shared components (`TopicRow`, `EntryRow`, `TopicHeader`, `TopicChip`, `ThumbnailStrip`, `PhotoGrid`) and the pure `EntryTimeline` helpers
  - `Screens/` — one file per screen or sheet; `RootView` owns the navigation stack
  - `SampleData/` — the seed, placeholder images, and `PreviewContainer`
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

No third-party packages, including test helpers and formatters. Apple frameworks only: SwiftUI, SwiftData, PhotosUI, Speech, AVFoundation.

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

### Shell mode (I1b)

`AppConfig.usesSampleData` is `true`: the app runs on a seeded in-memory container (`SampleData.makeContainer()`) and **nothing persists**. Buttons, menus, and fields render but only navigation and presentation work. **I2 flips the switch to `false`**, which moves the app to `ModelContainerFactory.makePersistent()`.

- No `modelContext.insert` / `delete` / `save` outside `SampleData` while in shell mode
- `SampleData.seed(into:)` has a `precondition` that the container is in-memory with CloudKit disabled. Sample data must never reach the persistent container
- Seed dates are fixed (September–October 2026) around `SampleData.now`, which shell mode and previews pass as `referenceDate`
- Seed photos are generated at seed time (`PlaceholderImage`); no image files are bundled or downloaded

### Previews

Every `#Preview` uses the seeded container through `.sampleData()` (defined beside `PreviewContainer`), which attaches `PreviewContainer.shared` and the seed's `referenceDate`. Fetch preview models with `PreviewContainer.topic(_:)` and `PreviewContainer.entry(in:at:)`. Each screen has light and dark previews.

## Data model

Models are defined inside `SchemaV1` (a `VersionedSchema`, version `1.0.0`) and exposed through top-level typealiases (`Topic`, `Entry`, `Photo`). App code never refers to the version namespace.

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

- User-facing deletes set `deletedAt`; they never call `modelContext.delete`
- `modelContext.delete` is only for permanent delete and purge. Cascade rules fire only then
- Every user-facing query filters `deletedAt == nil`

## Containers

`ModelContainerFactory` produces both stores:

- `makePersistent()` — the CloudKit-backed store. Only the running app calls it
- `makeInMemory()` — in-memory, CloudKit disabled. **Tests, previews, and shell mode always use this one**

Unit tests are hosted in the app, so the app launches during `make test`. `CommonplaceApp` detects a test run (the `XCTestConfigurationFilePath` environment variable) and uses an empty, unseeded in-memory container, so the CloudKit store is never created from tests. `ModelContainerFactoryTests` guards that the variable is set.

No sample or seed data is ever inserted into the persistent container.
