# SceneBox redesign (from 1.9.0)

| What | File |
|---|---|
| Audit: scores and the 15 ranked UX problems | [audit.md](audit.md) |
| Flows and pain points (researcher) | [research.md](research.md) |
| Three directions explored | [directions.md](directions.md), [shots/sheet-directions.jpg](shots/sheet-directions.jpg) |
| **Chosen direction and spec** | [chosen.md](chosen.md), [shots/sheet-chosen.jpg](shots/sheet-chosen.jpg) |
| Before (1.9.0 screenshots) | [shots/sheet-before.jpg](shots/sheet-before.jpg) |

- **Rebuild mockups:** run `python3 directions/build.py`, then `node render.mjs <chrome-headless-shell> shots directions/*.html sheet-*.html`.
- **Agents:** in `.claude/agents/` (`ui-ux-director`, `ux-researcher`).
