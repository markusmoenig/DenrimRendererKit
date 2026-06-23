#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SAMPLES="${1:-1}"
WIDTH="${2:-320}"
HEIGHT="${3:-180}"
OUTPUT="${4:-/tmp/denrim-dining-room.png}"

cd "$ROOT_DIR"
mkdir -p "$(dirname "$OUTPUT")"

swift run -c release denrim-render-preview \
    "$OUTPUT" \
    "$SAMPLES" \
    "$WIDTH" \
    script \
    beauty \
    Examples/SceneScripts/Quality/DiningRoom/dining-room.denrim \
    --width "$WIDTH" \
    --height "$HEIGHT"
