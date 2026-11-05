#!/bin/bash
# Boots a simulator, seeds sample data, and captures the main screens.
# Used by .github/workflows/screenshots.yml for visual review without a Mac.
# Needs: UDID (simulator), APP (path to the built .app).
set -uo pipefail

BUNDLE=app.scenebox.SceneBox
OUT=shots
mkdir -p "$OUT"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"

# First launch creates the data container; it's also what a new viewer sees.
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
shot() {    # shot <name> <seconds to wait>
  sleep "$2"
  xcrun simctl io "$UDID" screenshot "$OUT/$1.png" >/dev/null && echo "captured $1"
}
shot 00-first-launch 8
xcrun simctl terminate "$UDID" "$BUNDLE" || true

DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
python3 "$(dirname "$0")/seed_screenshots.py" "$DATA"

launch() {  # launch <args...>
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  sleep 1
  xcrun simctl launch "$UDID" "$BUNDLE" -SBScreenshots YES "$@" >/dev/null
}

launch;                                   shot 01-home 16
launch -SBInitialTab library;             shot 02-library-downloads 8
launch -SBInitialTab library -SBExpandAll YES; shot 03-library-expanded 8
launch -SBInitialTab search;              shot 04-search 12
launch -SBInitialTab profile;             shot 05-profile 6
launch -SBOpenDetail series/tt0903747;    shot 06-detail-series 16
launch -SBOpenDetail movie/tt1375666;     shot 07-detail-movie 16
launch -SBInitialTab library -SBExpandAll YES -SBOpenDetail series/tt0903747; shot 08-detail-over-library 16
launch -SBHomeRow series-top;             shot 09-home-top10 18
launch -SBOpenDetail series/tt0903747 -SBDetailScroll episodes; shot 10-detail-episodes 20
launch -SBInitialTab search -SBSearchQuery "breaking";   shot 11-search-results 12
launch -SBInitialTab search -SBSearchQuery "zqxjvbnmw";  shot 12-search-no-results 12
INCEPTION=fedcba9876543210fedcba9876543210fedcba98
launch -SBInitialTab library -SBPlayDownload $INCEPTION -SBPlayerPause YES;  shot 13-player 18
launch -SBInitialTab library -SBPlayDownload $INCEPTION -SBCastPicker YES;   shot 14-cast-picker 16
launch -SBInitialTab library -SBPlayDownload $INCEPTION -SBCastPreview YES;  shot 15-cast-playing 16
# The player turns the screen sideways; the capture stays portrait.
for f in 13-player 14-cast-picker 15-cast-playing; do sips -r 270 "$OUT/$f.png" >/dev/null 2>&1 || true; done

# A new viewer: same profile, nothing watched, saved or downloaded.
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
python3 "$(dirname "$0")/seed_screenshots.py" "$DATA" --empty
launch -SBInitialTab library;             shot 16-library-empty 8
launch;                                   shot 17-home-new-viewer 16
ls -la "$OUT"
