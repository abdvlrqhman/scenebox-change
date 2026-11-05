# SceneBox redesign (1.9.0 → 2.0 "Noir Lumière")

| What | File |
|---|---|
| **Before / after (CI screenshots, same seeded data)** | [shots/sheet-before-after.jpg](shots/sheet-before-after.jpg) |
| Audit: scores and the 15 ranked UX problems | [audit.md](audit.md) |
| Flows and pain points (researcher) | [research.md](research.md) |
| First round: three flow directions | [directions.md](directions.md), [shots/sheet-directions.jpg](shots/sheet-directions.jpg) |
| Flow spec kept from round one ("Marquee Up Next") | [chosen.md](chosen.md), [shots/sheet-chosen.jpg](shots/sheet-chosen.jpg) |
| Bold visual directions (Lumière, Noir, Marquee) | [shots/sheet-bold.jpg](shots/sheet-bold.jpg) |
| Before (1.9.0 screenshots) | [shots/sheet-before.jpg](shots/sheet-before.jpg) |

## What shipped

The director merged Noir's black canvas with Lumière's light and type into **Noir Lumière**. The flow fixes from `chosen.md` were kept:
- Play skips the version list.
- 3 tabs.
- Up next on Home.
- State written in words.

The rules live in `WatchBox/Shared/UI/Theme.swift` and in the director's brief, `.claude/agents/ui-ux-director.md`.

The bar for each screen:
- The director scores it 9/10 or higher, with no must-fix.
- Side by side with 1.9.0, it reads as clearly new.
- At most 4 rounds per screen.

| Screen | Rounds | Final | Clearly new | Left |
|---|---|---|---|---|
| Home | 3 | 9.0 | yes | none |
| Title page | 4 | 8.8 | yes | Episode hairlines now stop at the gutter (fixed after the last round). |
| Search | 4 (cap) | 8.8 | yes | Fixed after the last round, not re-judged: a new query clears the old rows, and slow catalogs show "Still searching". Left: no hint that TV shows are still loading. |
| My Stuff | 4 (cap) | 8.6 | yes | Fixed after the last round, not re-judged: play buttons are quiet, the resume point is in words ("2.6 GB   1h 20m left"), episode codes are in SF Pro, the bars line up. Left: the summary doesn't count paused downloads, and expanded shows sit on grey. |
| Player | 4 (cap) | 8.7 | partly | Subtitles can't be lifted above the scrubber because the SwiftVLC source isn't vendored, so a stronger scrim is used instead. |
| Cast | 3 | 9.0 | yes | none |
| Settings | 4 (cap) | 8.5 | yes | Fixed after the last round, not re-judged: the subtitle preview sits on the 20 pt gutter. Left: the footers run 4 to 8 lines. |
| First run | 3 | 9.0 | new screen | none |
| Create profile | 3 | 8.8 | yes | Swatches now have 44 pt targets (fixed after the last round). |

Final verdict: "Next to 1.9.0, this is clearly a different and better app."

Deliberately kept:
- The launch screen and app icon keep the yellow mark. That is the brand, not chrome.
- Menu items stay in title case, as iOS menus are.

Not done:
- Casting from the title page.
- Up next continuing on the TV.
- Zoom transitions.

## Rebuild

- **Mockups:** run `python3 directions/build.py` and `python3 directions/bold.py`, then `node render.mjs <chrome-headless-shell> shots directions/*.html sheet-*.html`.
- **Before/after sheet:** run `python3 before_after.py <1.9.0 shots dir> <2.0 shots dir>`, then `node render.mjs <chrome-headless-shell> shots sheet-before-after.html`. The shots come from the `screenshots` artifact of `screenshots.yml`.
- **Agents:** they live in `.claude/agents/` (`ui-ux-director`, `ux-researcher`).
