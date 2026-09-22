# SceneBox

![SceneBox on Mac and iPhone](website/images/mac-detail.png)

Torrent streaming client for iOS, iPadOS, tvOS and Mac (Catalyst), written in SwiftUI.

## Important

SceneBox is a media player and BitTorrent/HTTP client. It does not provide, host, index, upload, store, or distribute any media content, and it has no affiliation with any content source.

- All catalog metadata, stream listings, and media files come from third-party services and peers that users configure or connect to. These services are independent of SceneBox, are not operated, controlled, endorsed, or reviewed by its author, and may be changed or removed at any time.
- Users are solely responsible for the content they choose to access, for ensuring they have the legal right to do so, and for complying with the copyright and other laws of their jurisdiction. The author does not encourage, condone, or accept responsibility for any infringing use.
- The software is provided "as is", without warranty of any kind, for personal and lawful use only. See [LICENSE](LICENSE).

If you are a rights holder and believe a third-party source accessible through this software infringes your rights, please contact that source directly, as the author has no control over it.

Sources come from Stremio-compatible addons. Streams play through a vendored
libtorrent engine and a local HTTP server feeding VLC; debrid-cached releases
play directly over HTTPS.

## Project layout

- `WatchBox/App` – app entry, root navigation
- `WatchBox/Core/Catalog` – addon queries, release parsing, TMDB
- `WatchBox/Core/TorrentEngine` – libtorrent session and the local stream server
- `WatchBox/Features` – screens (Home, Search, Detail, Player, Library, Profiles, Downloads, Settings)
- `WatchBox/Shared` – models, UI components, theme
- `LibTorrent` – prebuilt `LibTorrentEngine.xcframework` (libtorrent 2.0.11 + OpenSSL) and its ObjC++ wrapper
- `scripts` – release packaging (`release-mac.sh`, `export-ipa.sh`)

## Get the IPA (no Mac needed)

Every push builds an unsigned IPA on a GitHub-hosted Mac
(`.github/workflows/build-ipa.yml`). Pushes to `main` publish it as the
`latest` release:

- Direct link: `https://github.com/abdvlrqhman/scenebox-change/releases/latest/download/SceneBox.ipa`
- Sign and install it with ESign, Sideloadly, AltStore, SideStore or TrollStore.

## Building locally

1. Xcode 26.4 or later (SwiftVLC needs Swift 6.3). Packages resolve on first open.
2. An Apple Developer account for device builds; set `DEVELOPMENT_TEAM`.

The engine is prebuilt; Xcode links the xcframework and does not compile
`TorrentEngine.mm`. Rebuild scripts live in `~/libtorrent-build/`.

## Accounts

There are no accounts. Profiles (up to 5, with photos), watch progress and
watchlists are stored on the device, per profile. Debrid and TMDB keys stay in
the device Keychain.

## Downloads

- Each episode is its own download, even when several come from one season
  pack. Episodes sharing a torrent download one after another; different
  torrents run side by side, up to the "Simultaneous downloads" limit.
- Episodes → Select Episodes / Download Season queues many at once.
- Downloads that were running resume after the app is relaunched.
- Background: iOS suspends apps a few seconds after they leave the screen,
  which drops every peer. While downloads run, SceneBox keeps itself alive with
  a silent, mixable audio session (Profile → Downloads → "Keep downloading in
  background"). On iOS 26+ an optional Live Activity shows progress via
  `BGContinuedProcessingTask`.

## Releases

```
scripts/release-mac.sh 1.0.0       # signed + notarized DMG
scripts/export-ipa.sh 1.0.0        # unsigned iOS IPA for sideloading
scripts/export-ipa.sh 1.0.0 tvos   # unsigned tvOS IPA for sideloading
```

## Debug flags

- `-WBAutoStreamMagnet '<magnet>'` – start a stream at launch
- `-WBAutoStreamFileIndex N` – pick a file inside a pack
- `-WBAutoSeekScript '40:+300,80:-120'` – scripted seeks

Metrics are written to `Documents/diagnostics/metrics.jsonl` in Debug builds.

## Contact

Questions, bug reports or feature ideas are welcome.

- **X / Twitter:** [@donbytyqi](https://x.com/donbytyqi) — follow for updates, or just ask me there
- **Email:** [spontaneousarray@gmail.com](mailto:spontaneousarray@gmail.com)
- **Issues:** open one on this repo for anything reproducible

## License

Personal, non-commercial use only. You may read the source and build it for
yourself; you may not sell it, redistribute it, or use it in a commercial
product or service. See [LICENSE](LICENSE).
