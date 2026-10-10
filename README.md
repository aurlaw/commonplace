# Commonplace

A personal structured journal for iPhone, in the tradition of a commonplace book: high-level **topics**, with **entries** logged against each. Entries can be typed or dictated, and can include photos.

This is a personal app, sideloaded rather than distributed through the App Store.

## Status

Early development. The app runs on the CloudKit-backed store, and topics and entries work: create, edit, archive, and sort topics; write, back-date, and edit entries; add photos from the library; record where an entry was written; page through a topic's entries. The rest exists as a visual shell, so dictation, Trash, and search are planned, not built.

## Planned features

- Create, rename, and archive topics
- Log entries against a topic: date, text, and any number of photos
- Voice entry through on-device transcription
- Works fully offline, syncing through iCloud when back online
- A per-topic timeline of entries
- Trash with restore, plus explicit permanent delete

## Tech

- Swift 6, SwiftUI, SwiftData
- Sync through the private CloudKit database
- iOS 26 or later, iPhone only
- No third-party packages

## Requirements

- Xcode 26
- An iOS 26 simulator (the Makefile defaults to "iPhone 17")
- To run on a device or sync: an Apple Developer team with the iCloud container `iCloud.com.aurlaw.commonplace`

## Building

```sh
make build   # build for the simulator
make test    # run the unit tests
make lint    # swift-format lint
```

Use a different simulator with `make test SIMULATOR="iPhone 17 Pro"`.

## Layout

| Path | Contents |
|---|---|
| `Commonplace/` | App sources |
| `CommonplaceTests/` | Unit tests (Swift Testing) |
| `CommonplaceUITests/` | UI tests (not run by `make test`) |
| `docs/design/` | Design reference |

Development conventions, including the rules the data model follows for CloudKit, are in [CLAUDE.md](CLAUDE.md).

## License

MIT — see [LICENSE](LICENSE).
