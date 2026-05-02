#!/usr/bin/env bash
# deploy.sh — Generate YAML from templates, sync to the HA config volume,
#             optionally push the Lovelace dashboard via WebSocket API, and
#             optionally reload/restart Home Assistant when the package
#             YAML actually changed.
#
# Usage:
#   ./deploy.sh [options] [TARGET]
#
# Options:
#   -r, --reload    Call homeassistant.reload_all after deploy if the
#                   package YAML changed. Soft: entities blip for 1-3s.
#   -R, --restart   Restart Home Assistant after deploy if the package
#                   YAML changed. Hard: ~60s downtime.
#   -f, --force     Reload/restart even if the package YAML didn't change.
#   -h, --help      Show this help.
#
# TARGET defaults to $HA_CONFIG_MOUNT (see .env), or /Volumes/config.
#
# What it does:
#   1. Load .env (fail fast on missing required vars).
#   2. Ensure the HA config volume is mounted; auto-mount on macOS via
#      `osascript` + Keychain credentials when HA_CONFIG_SMB_URL is set.
#   3. envsubst the *.tpl files into the target.
#   4. If HA_URL + HA_TOKEN are set, push the rendered dashboard to HA via
#      the Lovelace WebSocket API.
#   5. If --reload/--restart and the package YAML changed, call the
#      matching HA service via REST API.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# --- Parse args ---
do_reload=false
do_restart=false
force=false
TARGET=""

usage() {
  awk '
    NR == 1           { next }            # skip shebang
    /^$/              { exit }            # stop at first blank line
    /^#/              { sub(/^# ?/, ""); print; next }
                      { exit }            # stop at first non-comment line
  ' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--reload)  do_reload=true; shift ;;
    -R|--restart) do_restart=true; shift ;;
    -f|--force)   force=true; shift ;;
    -h|--help)    usage; exit 0 ;;
    -*)           echo "❌ Unknown option: $1" >&2; usage; exit 2 ;;
    *)
      if [[ -z "$TARGET" ]]; then
        TARGET="$1"; shift
      else
        echo "❌ Unexpected argument: $1" >&2; exit 2
      fi
      ;;
  esac
done

if $do_reload && $do_restart; then
  echo "❌ --reload and --restart are mutually exclusive." >&2
  exit 2
fi

# --- Load .env ---
if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ .env file not found: $ENV_FILE" >&2
  echo "   Copy .env.example to .env and fill in your values." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# --- Validate required vars ---
for var in GOE_SERIAL TIBBER_HOME IPHONE_DEVICE TIBBER_GRAPH_CAMERA; do
  if [[ -z "${!var:-}" ]]; then
    echo "❌ Missing required variable: $var (check your .env file)" >&2
    exit 1
  fi
done

TARGET="${TARGET:-${HA_CONFIG_MOUNT:-/Volumes/config}}"

# --- Mount helpers ---
is_mounted() {
  # Match exactly ' on <TARGET> (' to avoid prefix collisions
  # (e.g. /Volumes/config vs /Volumes/config-backup).
  mount | grep -Fq " on $1 ("
}

ensure_mounted() {
  if is_mounted "$TARGET" && [[ -r "$TARGET" ]]; then
    return 0
  fi

  if [[ -z "${HA_CONFIG_SMB_URL:-}" ]]; then
    echo "❌ Target not mounted: $TARGET" >&2
    echo "   Either mount it manually in Finder, or set HA_CONFIG_SMB_URL in" >&2
    echo "   .env (e.g. smb://user@host/share) to enable auto-mount." >&2
    exit 1
  fi

  echo "📡 Mounting $HA_CONFIG_SMB_URL ..."
  # osascript uses the macOS Keychain for the password — works silently
  # after the share has been mounted manually once with "Remember password".
  if ! osascript -e "mount volume \"$HA_CONFIG_SMB_URL\"" >/dev/null 2>&1; then
    echo "❌ Auto-mount failed." >&2
    echo "   Mount the share manually in Finder once so macOS caches the" >&2
    echo "   credentials in the Keychain, then retry." >&2
    exit 1
  fi

  # osascript can return before the mount point appears — poll briefly.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if is_mounted "$TARGET" && [[ -r "$TARGET" ]]; then
      return 0
    fi
    sleep 0.3
  done

  echo "❌ Mount reported success but target is still not accessible: $TARGET" >&2
  exit 1
}

ensure_mounted

echo "🚀 Deploying to $TARGET ..."
echo "   GOE_SERIAL=$GOE_SERIAL"
echo "   TIBBER_HOME=$TIBBER_HOME"
echo "   IPHONE_DEVICE=$IPHONE_DEVICE"

# --- Ensure output subfolder exists ---
OUT_DIR="$TARGET/ha-cost-optimized-ev-charging"
mkdir -p "$OUT_DIR"

# --- Render templates. Package changes drive the optional HA reload below,
#     so track whether its output differs from what's already on disk. ---
render() {
  local src="$1" dest="$2"
  envsubst < "$src" > "$dest.new"
  if [[ -f "$dest" ]] && cmp -s "$dest.new" "$dest"; then
    rm "$dest.new"
    return 1  # unchanged
  fi
  mv "$dest.new" "$dest"
  return 0  # changed
}

package_changed=false
dashboard_changed=false
widget_changed=false

if render "$SCRIPT_DIR/packages/ev-goe-tibber.yaml.tpl" "$OUT_DIR/ev-goe-tibber.yaml"; then
  package_changed=true
fi
if render "$SCRIPT_DIR/dashboard/ev-goe-tibber-dashboard.yaml.tpl" "$OUT_DIR/ev-goe-tibber-dashboard.yaml"; then
  dashboard_changed=true
fi
if render "$SCRIPT_DIR/dashboard/ev-widget-card.yaml.tpl" "$OUT_DIR/ev-widget-card.yaml"; then
  widget_changed=true
fi

mark() { $1 && echo "✳️  changed" || echo "  unchanged"; }
echo "✅ Files synced:"
echo "   $OUT_DIR/ev-goe-tibber.yaml            $(mark $package_changed)"
echo "   $OUT_DIR/ev-goe-tibber-dashboard.yaml  $(mark $dashboard_changed)"
echo "   $OUT_DIR/ev-widget-card.yaml           $(mark $widget_changed)"

# --- HA REST helper (curl-based, no Python dependency) ---
# homeassistant.reload_all can take 30-120s on large setups because HA
# blocks the API response until every domain has finished reloading. A
# strict curl timeout would therefore misreport a successful reload as a
# failure. We set a generous timeout and, if it still trips, probe
# /api/config to distinguish "HA is still working" from "HA is dead".
HA_SERVICE_TIMEOUT_S=180

ha_is_alive() {
  curl --fail --silent --max-time 5 \
    -H "Authorization: Bearer $HA_TOKEN" \
    "${HA_URL%/}/api/config" >/dev/null 2>&1
}

ha_service_call() {
  local service="$1"
  local url="${HA_URL%/}/api/services/${service/./\/}"
  local http_code

  # --write-out captures the status code; --output /dev/null discards the
  # body; --fail maps 4xx/5xx to curl exit code 22.
  http_code=$(
    curl --silent --show-error --max-time "$HA_SERVICE_TIMEOUT_S" \
      --output /dev/null --write-out '%{http_code}' \
      -X POST \
      -H "Authorization: Bearer $HA_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{}' \
      "$url"
  ) || {
    local exit_code=$?
    # curl exit 28 = timeout. HA may still be finishing the reload, so
    # give it a moment and then probe the API. If it responds, the
    # reload most likely went through.
    if [[ $exit_code -eq 28 ]]; then
      echo "⏳ Service call exceeded ${HA_SERVICE_TIMEOUT_S}s — probing HA..." >&2
      sleep 3
      if ha_is_alive; then
        echo "ℹ️  HA is back and healthy; treating reload as completed." >&2
        return 0
      fi
      echo "❌ HA is not responding after timeout." >&2
      return 1
    fi
    echo "❌ curl failed with exit code $exit_code." >&2
    return 1
  }

  if [[ "$http_code" != "200" ]]; then
    echo "❌ HA returned HTTP $http_code for $service." >&2
    return 1
  fi
  return 0
}

# --- Optional: push dashboard via HA WebSocket API ---
push_dashboard() {
  local url_path="${HA_DASHBOARD_URL_PATH:-ev-charging}"
  local updater="$SCRIPT_DIR/tools/ha_update_dashboard.py"
  local rendered="$OUT_DIR/ev-goe-tibber-dashboard.yaml"

  if [[ ! -x "$updater" ]]; then
    echo "⚠️  Dashboard updater not executable: $updater — skipping API push." >&2
    return 0
  fi
  if ! command -v uv >/dev/null 2>&1; then
    echo "⚠️  'uv' not found in PATH — skipping API push." >&2
    echo "   Install: https://docs.astral.sh/uv/getting-started/installation/" >&2
    return 0
  fi

  echo ""
  echo "📡 Pushing dashboard '$url_path' to $HA_URL ..."
  "$updater" "$url_path" "$rendered"
}

if [[ -n "${HA_URL:-}" && -n "${HA_TOKEN:-}" ]]; then
  if $dashboard_changed || $force; then
    push_dashboard
  else
    echo ""
    echo "ℹ️  Dashboard YAML unchanged — skipping API push (pass --force to push anyway)."
  fi
else
  echo ""
  echo "ℹ️  Dashboard API push disabled (HA_URL / HA_TOKEN not set in .env)."
fi

# --- Optional: reload or restart HA ---
# Dashboard/widget changes don't need a reload (dashboard is pushed via API,
# widget is a snippet for the user to paste elsewhere). Only package YAML
# drives this.
if $do_reload || $do_restart; then
  if [[ -z "${HA_URL:-}" || -z "${HA_TOKEN:-}" ]]; then
    echo "" >&2
    echo "❌ --reload/--restart requires HA_URL and HA_TOKEN in .env." >&2
    exit 1
  fi

  if ! $package_changed && ! $force; then
    echo ""
    echo "ℹ️  Package YAML unchanged — skipping reload (pass --force to reload anyway)."
  elif $do_reload; then
    echo ""
    echo "🔄 Calling homeassistant.reload_all on $HA_URL ..."
    if ha_service_call "homeassistant.reload_all"; then
      echo "✅ Reload triggered. Entities may blink for 1-3 seconds."
    else
      echo "❌ Reload call failed." >&2
      exit 1
    fi
  elif $do_restart; then
    echo ""
    echo "🔁 Calling homeassistant.restart on $HA_URL ..."
    echo "   HA will be unavailable for ~60 seconds."
    if ha_service_call "homeassistant.restart"; then
      echo "✅ Restart triggered."
    else
      echo "❌ Restart call failed." >&2
      exit 1
    fi
  fi
else
  if $package_changed; then
    echo ""
    echo "👉 Package YAML changed. To apply, run one of:"
    echo "     ./deploy.sh --reload    # soft, ~3s blip"
    echo "     ./deploy.sh --restart   # hard, ~60s downtime"
    echo "   …or call homeassistant.reload_all / restart via the UI."
  fi
fi
