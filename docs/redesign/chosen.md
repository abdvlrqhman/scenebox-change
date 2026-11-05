# Chosen direction: "Marquee Up Next"

The `ui-ux-director` picked a merge of the three directions:
- **From B1:** Home's watch-first top.
- **From A1:** the cinematic hero, shown to new viewers, and the Keep watching stills.
- **From A2:** the whole title page.
- **From C:** status written in the text line, and the type filter (moved to Search).

**Rejected:** B2's sticky bar and episode carousel, C1's vertical feed, and C2's centred layout and tabs.

Mockups: `shots/M1-home-returning.jpg` … `shots/M5-my-stuff.jpg`, all on one page in `shots/sheet-chosen.jpg`.

Director's scores for the drafts:

| Draft | Score |
|---|---|
| A1 | 7.5 |
| A2 | 8.0 |
| B1 | 8.0 |
| B2 | 6.3 |
| C1 | 6.7 |
| C2 | 7.0 |

## Structure
- **Tabs:** Home, Search, My Stuff.
- **Settings:** the avatar in every tab's header opens profiles and Settings.
- **Title pages** are pushed.
- **The player** is full screen; while casting, a mini bar sits above the tabs.

## Screens

### Home
- **Top slot, one component with two states:**
  - Something in progress: the **Up next** card (still, trimmed logo, "S1 E4 Cancer Man 46m Ready offline") and a yellow **Play next episode** or **Resume**.
  - Nothing in progress: the **marquee hero**, which changes only when swiped.
- **Rows:**
  - **Keep watching:** 16:9 stills that play when tapped. A long press offers the title page, Remove and Mark watched.
  - Watchlist, Because you watched, Top 10 with the numerals, and New.
- **Offline:** local rows stay. The catalog rows become one line, "You're offline. Downloads still play.", with Retry.

### Title page
- **Header:** full-bleed backdrop and the trimmed logo on the facts line.
- **Actions:**
  - A 56 pt yellow **Play / Resume** button with the time left.
  - Round **Download** and **Save** buttons.
  - **TV** and **Share** in the top bar.
  - An overflow menu with *Choose another version* and *Mark as watched*.
- **Series:**
  - A two-line synopsis, then season chips (a menu when there are more than 6).
  - Compact episode rows: still, name, runtime and state in text, and a 44 pt download button. Tapping a row plays it.
  - "Download season" in the chip's menu shows the size and has a Cancel.
- **Then:** Cast & crew, Details, More like this.

### Search
- The field is focused when you open it.
- Shows / Movies / Anime chips and genre chips stay while you type.
- Results show title, year and type, with exact matches first.
- No results offers suggestions and a genre to browse.

### My Stuff
- A neutral segment: Downloads / Watchlist / History.
- **Downloads:**
  - "Ready offline" first, then "Downloading" (size, Pause, Cancel, Waiting for Wi-Fi).
  - A storage card with **Remove watched**.
  - Episode names on every row.

### Player
- **Top bar:** Close, the title and episode, then CC, TV and Settings. At most 4 icons, each 44 pt.
- **Transport:** white glass, with a yellow scrubber and a Next episode button. No swarm stats; those move to Advanced.
- **CC sheet:**
  - language, device language and recent ones first
  - size S / M / L
  - Earlier / Later sync
  - Translate
  - Other subtitle files
- **Settings sheet:** audio, speed, aspect, Try another version.
- **Failure:** the app tries another version itself and keeps your place, then offers Retry, Try another version and Close.

### Cast
- Starts from the title page or the player.
- **"Play on TV" sheet:** clean device names; "TV not listed?" and "Watch on a computer" as rows.
- **Casting screen:**
  - The artwork framed as a TV.
  - The same transport as the phone.
  - Subtitles re-sent automatically, and up-next continues on the TV.

### First run
1. Name and colour; skipping creates "Me".
2. How to stream: peer-to-peer, with one privacy line, or a debrid account whose key is checked, with a QR code or phone handoff for TV.
3. Language from the device; Wi-Fi-only downloads on.

### Settings
- Profiles as a row of avatars.
- Groups:
  - Playback & subtitles.
  - Downloads.
  - Streaming: mode, a debrid key showing Valid or Expired, sources.
  - Actor photos (TMDB key).
  - Advanced, collapsed: sort, peers, port, trackers, buffer, cache, stream stats.
  - About.

### Empty, error and offline states
- One state component: what happened, what the app already did, and one action. Never a lone Close.
- Offline is a banner, not a page.

## Rebuild order
1. **Foundations:**
   - Display type that scales with Dynamic Type.
   - 44 pt buttons.
   - Neutral segments and toggles.
   - The state component and the offline banner.
   - These are shared with tvOS, so it keeps building.
2. **Title page and the play path:** Play skips the picker, and loading and errors can recover. Problems 1, 3, 4 and 9.
3. **Player and CC sheet.** Problems 3, 11 and 13.
4. **Home.** Problems 2 and 5; needs step 2.
5. **Tabs, My Stuff, Settings and first run together,** so the tab bar changes once. Problems 6, 7 and 12.
6. **Search.** Problem 10.
7. **Cast.** Problem 15; it's the least severe, and its hand-back code is the riskiest to touch.

After each screen: CI screenshots, then a director round. Each screen needs ≥ 9/10 and no must-fix, with at most 4 rounds.
