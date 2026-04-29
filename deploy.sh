#!/usr/bin/env bash
# deploy.sh — Generate YAML from templates using .env values and copy to HA config.
#
# Usage:
#   ./deploy.sh          # deploy to default target (/Volumes/config)
#   ./deploy.sh /path    # deploy to custom target

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-/Volumes/config}"
ENV_FILE="$SCRIPT_DIR/.env"

# --- Load .env ---
if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ .env file not found: $ENV_FILE"
  echo "   Copy .env.example to .env and fill in your values."
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

# --- Validate required vars ---
for var in GOE_SERIAL TIBBER_HOME IPHONE_DEVICE TIBBER_GRAPH_CAMERA; do
  if [[ -z "${!var:-}" ]]; then
    echo "❌ Missing required variable: $var (check your .env file)"
    exit 1
  fi
done

# --- Check target ---
if [[ ! -d "$TARGET" ]]; then
  echo "❌ Target not found: $TARGET"
  echo "   Is the network volume mounted?"
  exit 1
fi

echo "🚀 Deploying to $TARGET ..."
echo "   GOE_SERIAL=$GOE_SERIAL"
echo "   TIBBER_HOME=$TIBBER_HOME"
echo "   IPHONE_DEVICE=$IPHONE_DEVICE"

# --- Ensure output subfolder exists ---
OUT_DIR="$TARGET/ha-cost-optimized-ev-charging"
mkdir -p "$OUT_DIR"

# --- Generate from templates ---
envsubst < "$SCRIPT_DIR/packages/ev-goe-tibber.yaml.tpl" > "$OUT_DIR/ev-goe-tibber.yaml"
envsubst < "$SCRIPT_DIR/dashboard/ev-goe-tibber-dashboard.yaml.tpl" > "$OUT_DIR/ev-goe-tibber-dashboard.yaml"
envsubst < "$SCRIPT_DIR/dashboard/ev-widget-card.yaml.tpl" > "$OUT_DIR/ev-widget-card.yaml"

echo "✅ Deployed:"
echo "   $OUT_DIR/ev-goe-tibber.yaml"
echo "   $OUT_DIR/ev-goe-tibber-dashboard.yaml"
echo "   $OUT_DIR/ev-widget-card.yaml"
echo ""
echo "👉 Restart Home Assistant to apply changes."
