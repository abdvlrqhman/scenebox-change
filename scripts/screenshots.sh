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

# First launch creates the data container.
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
sleep 6
xcrun simctl terminate "$UDID" "$BUNDLE" || true

DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
python3 "$(dirname "$0")/seed_screenshots.py" "$DATA"

launch() {  # launch <args...>
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  sleep 1
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
}

shot() {    # shot <name> <seconds to wait>
  sleep "$2"
  xcrun simctl io "$UDID" screenshot "$OUT/$1.png" >/dev/null && echo "captured $1"
}

launch;                                   shot 01-home 16
launch -SBInitialTab library;             shot 02-library-downloads 8
launch -SBInitialTab library -SBExpandAll YES; shot 03-library-expanded 8
launch -SBInitialTab search;              shot 04-search 12
launch -SBInitialTab profile;             shot 05-profile 6
launch -SBOpenDetail series/tt0903747;    shot 06-detail-series 16
launch -SBOpenDetail movie/tt1375666;     shot 07-detail-movie 16
launch -SBInitialTab library -SBExpandAll YES -SBOpenDetail series/tt0903747; shot 08-detail-over-library 16
ls -la "$OUT"
