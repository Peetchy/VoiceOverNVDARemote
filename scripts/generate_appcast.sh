#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPCAST_PATH="${1:-$ROOT_DIR/dist/appcast.xml}"

: "${APPCAST_VERSION:?Set APPCAST_VERSION}"
: "${APPCAST_BUILD:?Set APPCAST_BUILD}"
: "${APPCAST_URL:?Set APPCAST_URL to the downloadable ZIP or DMG URL}"
: "${APPCAST_LENGTH:?Set APPCAST_LENGTH to the file size in bytes}"
: "${APPCAST_SIGNATURE:=}"
: "${APPCAST_MIN_SYSTEM:=14.0}"
: "${APPCAST_PUBDATE:=$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")}"

cat > "$APPCAST_PATH" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>VO NVDA Remote Updates</title>
    <link>${APPCAST_URL}</link>
    <description>Release feed for VO NVDA Remote</description>
    <language>en</language>
    <item>
      <title>Version ${APPCAST_VERSION}</title>
      <pubDate>${APPCAST_PUBDATE}</pubDate>
      <sparkle:version>${APPCAST_BUILD}</sparkle:version>
      <sparkle:shortVersionString>${APPCAST_VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${APPCAST_MIN_SYSTEM}</sparkle:minimumSystemVersion>
      <enclosure
        url="${APPCAST_URL}"
        length="${APPCAST_LENGTH}"
        type="application/octet-stream"
        sparkle:edSignature="${APPCAST_SIGNATURE}" />
    </item>
  </channel>
</rss>
EOF

echo "Created appcast at: $APPCAST_PATH"
