#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DEST_DIR="$ROOT_DIR/Examples/Assets/StanfordDragon/Meshes"
DEST_FILE="$DEST_DIR/dragon_vrip_res4.ply"
ARCHIVE_URL="https://graphics.stanford.edu/pub/3Dscanrep/dragon/dragon_recon.tar.gz"

mkdir -p "$DEST_DIR"

if [ -f "$DEST_FILE" ]; then
    echo "Stanford Dragon already exists at $DEST_FILE"
    exit 0
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

echo "Downloading Stanford Dragon reconstruction archive..."
curl -L "$ARCHIVE_URL" -o "$TMP_DIR/dragon_recon.tar.gz"

echo "Extracting dragon_vrip_res4.ply..."
tar -xzf "$TMP_DIR/dragon_recon.tar.gz" -C "$TMP_DIR" dragon_recon/dragon_vrip_res4.ply
mv "$TMP_DIR/dragon_recon/dragon_vrip_res4.ply" "$DEST_FILE"

echo "Wrote $DEST_FILE"

