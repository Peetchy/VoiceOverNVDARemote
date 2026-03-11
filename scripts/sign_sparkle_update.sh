#!/usr/bin/env bash
set -euo pipefail

UPDATE_FILE="${1:?Usage: sign_sparkle_update.sh <update-file>}"

if [[ -z "${SPARKLE_PRIVATE_ED_KEY:-}" ]]; then
  echo "SPARKLE_PRIVATE_ED_KEY is required" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

PRIVATE_KEY_PATH="$TMP_DIR/private.pem"
printf '%s\n' "$SPARKLE_PRIVATE_ED_KEY" > "$PRIVATE_KEY_PATH"

openssl pkeyutl -sign -inkey "$PRIVATE_KEY_PATH" -in "$UPDATE_FILE" | base64 | tr -d '\n'
