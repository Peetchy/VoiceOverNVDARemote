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

if command -v python3 >/dev/null 2>&1 && python3 -c "import cryptography" >/dev/null 2>&1; then
  PRIVATE_KEY_PATH="$PRIVATE_KEY_PATH" UPDATE_FILE="$UPDATE_FILE" python3 - <<'PY'
import base64
import os
import pathlib
import sys

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

private_key_path = pathlib.Path(os.environ["PRIVATE_KEY_PATH"])
update_file_path = pathlib.Path(os.environ["UPDATE_FILE"])

private_key = serialization.load_pem_private_key(private_key_path.read_bytes(), password=None)
if not isinstance(private_key, Ed25519PrivateKey):
    print("SPARKLE_PRIVATE_ED_KEY is not an Ed25519 private key", file=sys.stderr)
    sys.exit(1)

signature = private_key.sign(update_file_path.read_bytes())
sys.stdout.write(base64.b64encode(signature).decode("ascii"))
PY
  exit 0
fi

if command -v openssl >/dev/null 2>&1; then
  OPENSSL_BIN="$(command -v openssl)"
  if "$OPENSSL_BIN" pkeyutl -help 2>&1 | grep -q -- '-rawin'; then
    "$OPENSSL_BIN" pkeyutl -sign -rawin -inkey "$PRIVATE_KEY_PATH" -in "$UPDATE_FILE" | base64 | tr -d '\n'
    exit 0
  fi
fi

echo "Unable to sign update: install python3 with cryptography or OpenSSL with Ed25519 raw signing support" >&2
exit 1
