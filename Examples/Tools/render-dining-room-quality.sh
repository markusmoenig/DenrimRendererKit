#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SAMPLES="${1:-}"
WIDTH="${2:-}"
HEIGHT="${3:-}"
OUTPUT="${4:-}"
SAMPLE_RADIANCE_CLAMP="${5:-}"
QUALITY="${6:-}"
BACKEND="${7:-}"

cd "$ROOT_DIR"

set -- swift run -c release denrim -- Examples/SceneScripts/Quality/DiningRoom/dining-room.denrim
[ -n "$OUTPUT" ] && set -- "$@" --output "$OUTPUT"
[ -n "$SAMPLES" ] && set -- "$@" --samples "$SAMPLES"
[ -n "$WIDTH" ] && set -- "$@" --width "$WIDTH"
[ -n "$HEIGHT" ] && set -- "$@" --height "$HEIGHT"
[ -n "$QUALITY" ] && set -- "$@" --quality "$QUALITY"
[ -n "$BACKEND" ] && set -- "$@" --backend "$BACKEND"
[ -n "$SAMPLE_RADIANCE_CLAMP" ] && set -- "$@" --sample-radiance-clamp "$SAMPLE_RADIANCE_CLAMP"

"$@"
