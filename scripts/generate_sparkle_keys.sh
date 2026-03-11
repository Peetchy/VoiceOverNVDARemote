#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-$(pwd)/keys}"
mkdir -p "$OUT_DIR"

PRIVATE_KEY_PATH="$OUT_DIR/sparkle_ed25519_private.pem"
PUBLIC_KEY_RAW_B64_PATH="$OUT_DIR/sparkle_public_ed_key.txt"
PUBLIC_KEY_PEM_PATH="$OUT_DIR/sparkle_ed25519_public.pem"

openssl genpkey -algorithm Ed25519 -out "$PRIVATE_KEY_PATH"
openssl pkey -in "$PRIVATE_KEY_PATH" -pubout -out "$PUBLIC_KEY_PEM_PATH"
openssl pkey -in "$PRIVATE_KEY_PATH" -pubout -outform DER | tail -c 32 | base64 > "$PUBLIC_KEY_RAW_B64_PATH"

echo "Private key: $PRIVATE_KEY_PATH"
echo "Public key PEM: $PUBLIC_KEY_PEM_PATH"
echo "Sparkle SUPublicEDKey: $(cat "$PUBLIC_KEY_RAW_B64_PATH")"
