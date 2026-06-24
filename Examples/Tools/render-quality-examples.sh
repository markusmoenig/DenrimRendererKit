#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SAMPLES="${1:-128}"
SIZE="${2:-512}"
SAMPLE_RADIANCE_CLAMP="${3:-24}"
QUALITY="${4:-interactive}"
BACKEND="${5:-automatic}"
OUTPUT_DIR="${DENRIM_QUALITY_OUTPUT_DIR:-/tmp/denrim-quality-examples}"

cd "$ROOT_DIR"
mkdir -p "$OUTPUT_DIR"

swift run denrim -- \
    Examples/SceneScripts/MaterialVariants/material-variants.denrim \
    --output "$OUTPUT_DIR/material-variants.png" \
    --samples "$SAMPLES" \
    --size "$SIZE" \
    --quality "$QUALITY" \
    --backend "$BACKEND" \
    --sample-radiance-clamp "$SAMPLE_RADIANCE_CLAMP"

swift run denrim -- \
    Examples/SceneScripts/MaterialVariants/glossy-metal-reference.denrim \
    --output "$OUTPUT_DIR/glossy-metal-reference.png" \
    --samples "$SAMPLES" \
    --size "$SIZE" \
    --quality "$QUALITY" \
    --backend "$BACKEND" \
    --sample-radiance-clamp "$SAMPLE_RADIANCE_CLAMP"

if [ ! -f Examples/Assets/StanfordDragon/Meshes/dragon_vrip_res4.ply ]; then
    ./Examples/Tools/fetch-stanford-dragon.sh
fi

swift run denrim -- \
    Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim \
    --output "$OUTPUT_DIR/dragon-material-variants.png" \
    --samples "$SAMPLES" \
    --size "$SIZE" \
    --quality "$QUALITY" \
    --backend "$BACKEND" \
    --sample-radiance-clamp "$SAMPLE_RADIANCE_CLAMP"
