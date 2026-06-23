#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SAMPLES="${1:-1}"
WIDTH="${2:-320}"
HEIGHT="${3:-180}"
OUTPUT="${4:-Examples/Benchmarks/dining-room-local-${WIDTH}x${HEIGHT}-${SAMPLES}spp.json}"

cd "$ROOT_DIR"
mkdir -p "$(dirname "$OUTPUT")"

swift run -c release denrim-render-benchmark \
    script \
    "$SAMPLES" \
    "$WIDTH" \
    Examples/SceneScripts/Quality/DiningRoom/dining-room.denrim \
    --width "$WIDTH" \
    --height "$HEIGHT" \
    --output "$OUTPUT"
