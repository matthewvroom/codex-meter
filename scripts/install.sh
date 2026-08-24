#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
"$ROOT/scripts/build-app.sh" "$ROOT/dist"
if [[ -d "/Applications/Utilities/Codex Meter.app" ]]; then
  DESTINATION="/Applications/Utilities/Codex Meter.app"
elif [[ -d "/Applications/Codex Meter.app" ]]; then
  DESTINATION="/Applications/Codex Meter.app"
else
  DESTINATION="/Applications/Codex Meter.app"
fi
DESTINATION_DIR="${DESTINATION:h}"
STAGE="$(mktemp -d /Applications/.codex-meter-install.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

pkill -x CodexMeter 2>/dev/null || true
ditto --norsrc --noextattr --noqtn --noacl "$ROOT/dist/Codex Meter.app" "$STAGE/Codex Meter.app"
xattr -cr "$STAGE/Codex Meter.app"
codesign --force --deep --sign - "$STAGE/Codex Meter.app"
codesign --verify --deep --strict "$STAGE/Codex Meter.app"

if [[ -d "$DESTINATION" ]]; then
  BACKUP="/Applications/.Codex Meter.previous.app"
  rm -rf "$BACKUP"
  ditto --norsrc --noextattr --noqtn --noacl "$DESTINATION" "$BACKUP"
  if [[ -w "$DESTINATION_DIR" ]]; then
    rm -rf "$DESTINATION"
    if ! mv "$STAGE/Codex Meter.app" "$DESTINATION"; then
      mv "$BACKUP" "$DESTINATION"
      exit 1
    fi
  elif [[ -w "$DESTINATION" ]]; then
    find "$DESTINATION" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    if ! ditto --norsrc --noextattr --noqtn --noacl "$STAGE/Codex Meter.app" "$DESTINATION"; then
      find "$DESTINATION" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
      ditto --norsrc --noextattr --noqtn --noacl "$BACKUP" "$DESTINATION"
      exit 1
    fi
  else
    echo "Cannot update $DESTINATION without administrator access" >&2
    exit 1
  fi
  rm -rf "$BACKUP"
else
  mv "$STAGE/Codex Meter.app" "$DESTINATION"
fi

codesign --verify --deep --strict "$DESTINATION"
open "$DESTINATION"
echo "Installed and opened $DESTINATION"
