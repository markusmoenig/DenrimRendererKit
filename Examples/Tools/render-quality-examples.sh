#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SAMPLES="${1:-128}"
SIZE="${2:-512}"

cd "$ROOT_DIR"
mkdir -p Examples/Renders

swift run denrim-render-preview \
    Examples/Renders/material-variants.png \
    "$SAMPLES" \
    "$SIZE" \
    script \
    beauty \
    Examples/SceneScripts/MaterialVariants/material-variants.denrim

swift run denrim-render-preview \
    Examples/Renders/glossy-metal-reference.png \
    "$SAMPLES" \
    "$SIZE" \
    script \
    beauty \
    Examples/SceneScripts/MaterialVariants/glossy-metal-reference.denrim

if [ ! -f Examples/Assets/StanfordDragon/Meshes/dragon_vrip_res4.ply ]; then
    ./Examples/Tools/fetch-stanford-dragon.sh
fi

swift run denrim-render-preview \
    Examples/Renders/dragon-material-variants.png \
    "$SAMPLES" \
    "$SIZE" \
    script \
    beauty \
    Examples/SceneScripts/MaterialVariants/dragon-material-variants.denrim
