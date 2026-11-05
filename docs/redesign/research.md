# SceneBox 1.9.0 UX research (flows and pain points)

By the `ux-researcher` agent, from the code at v1.9.0. Default settings throughout. Confidence high unless marked (M).

## Flow maps (iPhone, tap counts in brackets)

**T1 First launch to the first frame**: 4–5 taps, typing, 3 loading screens.
1. "Create your profile": a name is required, with no skip.
2. Home with placeholder rows. Tap a poster [1].
3. The title page spins until details arrive. Tap Watch [1].
4. A sheet, "Choose a release to stream", lists raw release names with 1080P, size, seeders, Debrid and Best pick chips. Pick one [1].
5. A loading screen cycles through "Fetching sources from peers…", "Starting stream…" and "3 sources · 1.2 MB/s". "Play now" appears once enough has buffered.
6. First frame. Arabic subtitles turn on automatically (the default is "ara").

**T2 Resume**: 3 taps, 3 waits.
1. Tap the Continue Watching card. It opens the title page, not the player.
2. Tap Resume.
3. The release list opens again; tap "Last watched".
4. Loading screen.
- A finished episode reads "S1 E3 Watched" instead of naming the next episode.
- Offline it's a dead end: Home shows only an error.

**T3 Find or browse**
- Search tab, then tap the field (it isn't focused for you). Results are a poster grid with no title, year or type.
- Genre: "Popular Movies ⌄", then Genre, then a pick [3].

**T4 Episodes**
1. Scroll past the actions, synopsis, cast and crew to reach Episodes.
2. Season menu [2], episode [1], release list [1].
- Next episode auto-picks a version whatever the setting says.
- No up-next while casting.

**T5 Download a season**
1. Download, then "Download Season" [2].
2. A blocking "Finding sources… 3 of 10" overlay appears, with no Cancel and no size estimate.
3. Downloads need the app alive and use cellular by default.
- There's no "delete watched".

**T6 Cast**
- Playback must already be buffering on the phone. Then screen, TV icon, TV [3].
- Changed subtitles need a manual "Send new subtitles to the TV".
- No casting from the title page; none on tvOS or Mac.

**T7 Subtitles while watching**
- Screen, sliders, Subtitles, Language, a language [4].
- Sync steppers are on the panel.
- Size isn't in the player.

**T8 Profile and accounts**
- Switching profile takes 4 taps.
- The debrid key is pasted with no check or validation.
- Settings mix viewer preferences with ports, trackers, peers and buffers.

## Pain points (ranked)

1. **Every play needs a release pick, Resume included.** Auto-pick is off by default.
2. **Continue Watching doesn't play.** The card goes to the title page, then Resume, then the release list.
3. **Offline is a dead end outside Library.** Home and title pages need the network.
4. **Torrent plumbing reaches the viewer.**
   - Seeders, peers called "sources", "torrent link could not be started", "Piece N failed hash check", "Looking for peers…".
5. **Recovering from failure is manual.** Error cards only offer Close; Play reopens the release list.
6. **The Profile tab is a settings dump.**
   - About 13 sections and 35+ controls.
   - Copy points to "Settings › Debrid", which doesn't exist.
   - The "Cast" section is actually the TMDB actor-photo key.
7. **There's no first-run setup.** The P2P privacy note sits in a footer, debrid is never offered, and subtitles default to Arabic.
8. **Debrid setup is unvalidated and goes stale.** tvOS means typing a key with the remote.
9. **Season download is clumsy.** No cancel, no size, a duplicated menu, and inconsistent auto-pick.
10. **Downloads are fragile and fill space quietly.** Cellular is on by default, there's no trip-ready state, no "remove watched", and streamed videos are silently kept.
11. **Subtitle controls are buried.** There's no CC button, and size can't be changed in the player.
12. **Casting starts only inside the player.** Subtitles need a manual re-send, and there's no up-next on the TV.
13. **Search is weak.** The field isn't focused, results are unlabelled posters, the type filter disappears while typing, and genres are buried.
14. **Series episodes sit at the bottom of the title page.**
15. **Profiles are shallow.** Preferences are app-wide, not per person (M).

## Missing states

- **Offline:** Home hides its local rows, and title pages have no cached fallback.
- **Cast permission denied:** no specific state (M).
- **Batch download:** no Cancel and no partial progress.
- **Downloads:** no free-space check (M).
- **Debrid:** no valid, invalid or expired key state.
- **Player:** no in-place error recovery.
- **Jargon:** release, seeding, magnet, metadata, tracker, peers, Max peers, Streaming port, Custom trackers, Player buffer.

## Quick wins

1. Turn Auto-pick on by default.
2. Keep Continue Watching and Watchlist visible above Home's error.
3. Add "Try another version" and "Retry" to player errors, and Cancel to batch downloads.
4. Default subtitles to the device language, and fix the "Settings ›" copy and the "Cast" section name.
5. Make the Continue Watching card play, or name the next episode.

## What a redesign should change structurally

- **One verb, Play.** Posters, Continue Watching and Up Next go straight to video; choosing a version is a fallback.
- **Choose how to stream once, at setup.** Peer-to-peer (with the privacy note) or a debrid account that's checked, with a phone or QR handoff for TV. After that, sources are invisible.
- **Tabs around the viewer.**
  - Home: what to watch next, working offline.
  - Search: focused field, labelled results, genre chips.
  - My Stuff: downloads, watchlist and history.
  - Settings behind the avatar, with Advanced hidden.
- **Offline as a real mode.** Cached title details, a "ready for your trip" state, and "remove watched".
- **One player panel** for subtitle language, size and sync. Casting from the title page, with up-next continuing on the TV.
- **Per-profile preferences.**
