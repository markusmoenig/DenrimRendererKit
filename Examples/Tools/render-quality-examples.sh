#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SAMPLES="${1:-128}"
SIZE="${2:-512}"
SAMPLE_RADIANCE_CLAMP="${3:-24}"
QUALITY="${4:-interactive}"
BACKEND="${5:-automatic}"

cd "$ROOT_DIR"
mkdir -p Examples/Renders

swift run denrim -- \
    Examples/SceneScripts/MaterialVariants/material-variants.denrim \
    --output Examples/Renders/material-variants.png \
    --samples "$SAMPLES" \
    --size "$SIZE" \
    --quality "$QUALITY" \
    --backend "$BACKEND" \
    --sample-radiance-clamp "$SAMPLE_RADIANCE_CLAMP"

swift run denrim -- \
    Examples/SceneScripts/MaterialVariants/glossy-metal-reference.denrim \
    --output Examples/Renders/glossy-metal-reference.png \
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
    --output Examples/Renders/dragon-material-variants.png \
    --samples "$SAMPLES" \
    --size "$SIZE" \
    --quality "$QUALITY" \
    --backend "$BACKEND" \
    --sample-radiance-clamp "$SAMPLE_RADIANCE_CLAMP"
