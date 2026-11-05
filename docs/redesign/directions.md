# SceneBox redesign: three directions

All three share the structural fixes from the research:
- "Play" goes straight to video; the version list is only a fallback.
- Three tabs: Home, Search, My Stuff (downloads, watchlist, history). Settings sits behind the avatar.
- Episodes come first on a series page.
- Offline keeps working.
- How to stream is chosen once, at setup.

They differ in what Home is for and in how the title page is built. Mockups (HTML, real catalog artwork) are in `shots/`; their sources are in `directions/`.

## A · Marquee: the cinema, evolved
`A1-marquee-home.png`, `A2-marquee-title.png`
- **Home** opens on a full-bleed featured title: the artwork runs under the status bar, with the logo, one line of facts and a single yellow Play. Swiping changes titles only when you swipe. Next comes **Up next**: 16:9 episode stills that play when tapped, saying "S1 E4 Cancer Man" rather than "Watched". The Top 10 rows and the rest follow.
- **Title page:** a full-bleed backdrop and the logo on the line of facts, then a 56 pt Resume button that carries the time left, two round companions, and a two-line synopsis. **Season chips and the episodes come right after.**
- **Signature:** the condensed billing-block type and the artwork-first hero. This is today's identity pushed to its edges.
- **Trade-off:** the safest direction, least new to learn. Home's first screen is spent on promotion more than on your own shows.

## B · Up Next: watch-first, one thumb
`B1-upnext-home.png`, `B2-upnext-title.png`
- **Home is "Up next":**
  - One large card shows the exact next thing to watch: still, logo, episode name, length, and "Ready offline" when it's downloaded.
  - A full-width **Play next episode** sits under it.
  - Then "Keep watching", then discovery rows.
- **Title page:**
  - A compact header (poster, title, facts, quiet icon actions for save, download, cast and share).
  - Episodes as big swipeable stills, so you scroll through the episodes themselves, not a list of names.
  - A **sticky Resume bar at the bottom**, where the thumb is.
- **Signature:** "what's next" is always one tap away, and the main action never leaves the bottom of the screen.
- **Trade-off:**
  - Strongest for people who watch series; less of a showcase for discovery.
  - The sticky bar hides the tab bar on title pages.

## C · Ambient: a feed of films
`C1-ambient-home.png`, `C2-ambient-title.png`
- **Home is a full-screen vertical feed:**
  - Each swipe brings one title, full-bleed, with its logo, a pitch, Play, Save and Details.
  - A glass segmented control switches between For you, Shows, Movies and Anime.
- **Title page** takes its colour from the artwork:
  - A centred, lit poster, the title in display type, then Resume.
  - Tabs: Episodes, About, More like this.
- **Signature:** discovery as a lean-back experience; every screen is one title's world.
- **Trade-off:**
  - The most distinctive and the most work.
  - Resume is buried behind the feed (it would need its own entry).
  - A centred layout breaks today's left-aligned system.
  - One title per screen is slow for people who know what they want.
