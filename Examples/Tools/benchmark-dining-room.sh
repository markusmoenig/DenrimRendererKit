#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SAMPLES="${1:-1}"
WIDTH="${2:-320}"
HEIGHT="${3:-180}"
OUTPUT="${4:-Examples/Benchmarks/dining-room-local-${WIDTH}x${HEIGHT}-${SAMPLES}spp.json}"
SAMPLE_RADIANCE_CLAMP="${5:-16}"
QUALITY="${6:-interactive}"
BACKEND="${7:-automatic}"
PNG_OUTPUT="${DENRIM_BENCHMARK_RENDER_OUTPUT:-/tmp/denrim-dining-room-benchmark.png}"

cd "$ROOT_DIR"
mkdir -p "$(dirname "$OUTPUT")"

swift run -c release denrim -- \
    Examples/SceneScripts/Quality/DiningRoom/dining-room.denrim \
    --output "$PNG_OUTPUT" \
    --samples "$SAMPLES" \
    --width "$WIDTH" \
    --height "$HEIGHT" \
    --quality "$QUALITY" \
    --backend "$BACKEND" \
    --sample-radiance-clamp "$SAMPLE_RADIANCE_CLAMP" \
    --report-output "$OUTPUT"
