# SceneBox 1.9.0 audit

By the `ui-ux-director` agent, from 18 CI screenshots and the code, together with the `ux-researcher` report (`research.md`). Every screen got the verdict **iterate**. The average is about **5.6/10**: the look is strong, but getting to the video is broken. Playing something takes three extra decisions, and nearly every failure ends at a lone Close button.

## Scores (1–10)
H = hierarchy, Cl = clarity, Fl = flow, Co = consistency, A11y = accessibility, De = delight.

| Screen | H | Cl | Fl | Co | A11y | De | Overall |
|---|---|---|---|---|---|---|---|
| First launch | 7 | 7 | 5 | 7 | 7 | 4 | 6.2 |
| Home | 6 | 6 | 4 | 7 | 6 | 7 | 6.0 |
| Home, Top 10 | 7 | 8 | 6 | 8 | 6 | 8 | 7.2 |
| Home, new viewer | 6 | 6 | 5 | 7 | 6 | 6 | 6.0 |
| Search, browsing | 6 | 5 | 5 | 7 | 5 | 6 | 5.7 |
| Search results | 5 | 4 | 5 | 7 | 5 | 5 | 5.2 |
| Search, no results | 7 | 7 | 4 | 8 | 7 | 4 | 6.2 |
| Title page, series | 7 | 6 | 4 | 6 | 6 | 7 | 6.0 |
| Episodes | 6 | 6 | 5 | 6 | 5 | 6 | 5.7 |
| Title page, movie | 7 | 6 | 5 | 6 | 6 | 7 | 6.2 |
| Title page from Library | 7 | 6 | 4 | 6 | 6 | 7 | 6.0 |
| Library › Downloads | 5 | 5 | 6 | 5 | 6 | 5 | 5.3 |
| Library, expanded | 5 | 4 | 6 | 5 | 6 | 5 | 5.2 |
| Library, empty | 6 | 7 | 4 | 6 | 7 | 4 | 5.7 |
| Profile | 4 | 3 | 4 | 5 | 7 | 3 | 4.3 |
| Rest of Settings | 3 | 2 | 4 | 5 | 7 | 2 | 3.8 |
| Player and its panel | 6 | 5 | 5 | 5 | 5 | 7 | 5.5 |
| Cast picker | 6 | 6 | 6 | 5 | 7 | 4 | 5.7 |
| Casting | 7 | 5 | 6 | 5 | 6 | 6 | 5.8 |
| Release picker | 4 | 3 | 3 | 4 | 6 | 3 | 3.8 |
| Stream loading | 7 | 5 | 6 | 7 | 6 | 7 | 6.3 |
| Error states | 6 | 4 | 3 | 5 | 6 | 3 | 4.5 |

## The 15 UX problems, ranked
1. **Every play goes through the release list, Resume included. (critical)** Auto-pick is off by default, so viewers have to judge torrent names. *Fix:* Play plays the best version, or the last one that worked. "Choose another version" is a secondary action.
2. **Continue Watching, the featured carousel and finished episodes don't lead to video. (critical)**
   - The Continue Watching card opens the title page.
   - The carousel has no Play button.
   - A finished episode says "Watched" instead of naming the next one.
   
   *Fix:* the card plays the next thing and names it.
3. **Failures end at a lone Close button. (critical)** One message even reads "Close the player and open the episode again." With torrents, failure is the common case. *Fix:* retry and switch version automatically first, keep your place, then offer Retry and Try another version.
4. **Torrent plumbing reaches the viewer. (major)** Peers, seeders, "torrent link", "Piece N failed hash check", and a peer count under the scrubber. *Fix:* talk in viewing states only (Starting, Slow connection, Ready offline, Couldn't play); diagnostics go under Advanced.
5. **Offline is a dead end outside Library. (major)** Home replaces your local rows with an error, and title pages need the network. *Fix:* local rows always render, with an offline banner and cached title pages.
6. **How you stream is never set up, and the defaults are wrong. (major)** Subtitles default to Arabic, cellular downloads are on, and the privacy note sits in a settings footer. *Fix:* a two-step first run: peer-to-peer or a checked debrid account (QR code for TV), then language from the device.
7. **Settings is a whole tab, and it's a dump. (major)** About 13 sections and 35+ controls. *Fix:* the avatar moves into the header. Settings becomes Playback & subtitles, Downloads, Streaming account and Profiles, with Advanced collapsed.
8. **Words collide. (major)**
   - "Cast" means the actors, playing on a TV, and the TMDB-key settings section.
   - "release", "source", "version" and "provider" all mean the video.
   - "Settings › Debrid" points to a screen that doesn't exist.
   
   *Fix:* one word per thing, and links that name a real place.
9. **On a series, the episodes are buried. (major)** They sit below the synopsis, cast and crew, in tall rows. *Fix:* lead with the next episode and the seasons; compact rows.
10. **Search is weak. (major)** The field isn't focused, results are unlabelled posters, the exact match ranks third, genres are buried, and no-results is a dead end.
11. **Subtitles are buried in the player. (major)** Changing language takes 4 taps, size isn't in the player, and casting needs a manual re-send. *Fix:* a CC button with one sheet for language, size and sync; casting re-sends on its own.
12. **Downloads are fragile and fill space quietly. (major)**
    - No Cancel or size on season downloads.
    - Cellular is on and there's no free-space check.
    - There's no "Remove watched".
    - Streamed videos are kept silently.
    - Library rows say "Watched" where the episode name belongs.
13. **Accessibility floor. (major)** Display type ignores Dynamic Type, player icons are 40 pt, tertiary text is about 3.5:1 contrast, and dark logos disappear on dark art.
14. **Yellow creeps in, and colour coding adds noise. (minor)** Library's segment and play discs, the settings toggles, the release picker's chips and the cast picker's Done are all yellow.
15. **Casting only starts inside a running player. (minor)** The TV's raw name shows twice, and there's no up-next on the TV.

## What must survive
**Strengths:**
- The dark canvas where artwork carries the colour.
- Condensed display titles.
- The Top 10 numerals.
- Title logos.
- Progress on posters.
- Resume naming the episode, with progress inside the button.
- The loading screen's backdrop and logo.
- The casting screen framed as a TV.
- Up Next with its countdown.
- Motion only on touch.
- Thorough VoiceOver labels.
- The tone of the empty-state copy.

**Features that must keep working:**
- Source ranking with health checks, and memory of the last version.
- Subtitle choice and sync per version, and translation.
- Audio kept across reconnects.
- DLNA casting and the computer page.
- Downloads: queue, season, background, Live Activity, storage cap.
- Debrid.
- Profiles, watchlist, history, "Because you watched", catalogs and deep links.
- Keyboard shortcuts and swipe gestures.
- tvOS has to keep compiling: some components are shared.

## Principles for the redesign
1. **Play is one tap.** Picking a version is recovery, not a step.
2. **The viewer never sees the swarm.**
3. **Failure fixes itself first;** never a lone Close.
4. **What's on the device always works.**
5. **Decide once,** at first run, with good defaults.
6. **The next episode leads.**
7. **One yellow and one verb per screen,** written into the components.
8. **One word per thing,** and every link names a real place.
