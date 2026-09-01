#!/usr/bin/env bash
# =====================================================================
#  setup-offline.sh
#
#  Linux/Raspberry Pi port of setup-offline.ps1
#
#  Run this ONCE while you still have internet (from the AviatorSite
#  folder):   ./setup-offline.sh
#
#  It downloads two things so index.html works with NO internet later:
#    1. the Leaflet map library  ->  ./lib
#    2. map image tiles for your flight area  ->  ./tiles
#
#  Re-running it is safe: tiles that already exist are skipped.
#
#  Requires: bash, curl, awk (all present by default on Raspberry Pi OS)
# =====================================================================

set -euo pipefail

# ---- bounding box of the area you want map coverage for (degrees) ----
#      defaults cover the city of Chandler, AZ (plus a little margin)
LAT_MIN="${LAT_MIN:-33.2986}"
LAT_MAX="${LAT_MAX:-33.3276}"
LON_MIN="${LON_MIN:--111.9075}"
LON_MAX="${LON_MAX:--111.8728}"

# ---- zoom levels to cache ----
#      MUST match minZoom / maxZoom in index.html's tileLayer(...).
#      Each extra zoom level roughly 4x's the tile count & download time.
ZOOM_MIN="${ZOOM_MIN:-10}"
ZOOM_MAX="${ZOOM_MAX:-20}"

# free tile servers want a real, identifiable User-Agent
UA="AviatorSite-offline-setup/1.0 (personal offline flight dashboard)"

# MapTiler API key - free tier, explicitly permits offline/cached tile use
# (unlike tile.openstreetmap.org, which blocked this exact bulk-download pattern)
MAPTILER_KEY="1M5tYuPCnSkU4K7WidLr"

# ---------------------------------------------------------------------
# 1. Leaflet library
# ---------------------------------------------------------------------
echo "Downloading Leaflet library..."
mkdir -p lib/images

BASE_URL="https://unpkg.com/leaflet@1.9.4/dist"
curl -sS -A "$UA" -o "lib/leaflet.js"  "$BASE_URL/leaflet.js"
curl -sS -A "$UA" -o "lib/leaflet.css" "$BASE_URL/leaflet.css"

# marker/control images referenced by leaflet.css (not strictly needed for
# this dashboard, but grabbing them keeps the library self-contained)
for img in marker-icon.png marker-icon-2x.png marker-shadow.png layers.png layers-2x.png; do
  if ! curl -sS -f -A "$UA" -o "lib/images/$img" "$BASE_URL/images/$img"; then
    echo "  WARNING: could not fetch image $img (safe to ignore)"
  fi
done
echo "  -> saved to ./lib"

# ---------------------------------------------------------------------
# 2. Map tiles
# ---------------------------------------------------------------------
# standard slippy-map math: lon/lat + zoom -> tile x/y
tile_x() {
  # args: lon zoom
  awk -v lon="$1" -v z="$2" 'BEGIN {
    print int((lon + 180.0) / 360.0 * (2 ^ z))
  }'
}
tile_y() {
  # args: lat zoom
  awk -v lat="$1" -v z="$2" 'BEGIN {
    pi = atan2(0, -1)
    rad = lat * pi / 180.0
    tan_rad = sin(rad) / cos(rad)
    print int((1.0 - log(tan_rad + (1.0 / cos(rad))) / pi) / 2.0 * (2 ^ z))
  }'
}

saved=0
skipped=0

for (( z=ZOOM_MIN; z<=ZOOM_MAX; z++ )); do

  x_start=$(tile_x "$LON_MIN" "$z")
  x_end=$(tile_x "$LON_MAX" "$z")
  y_start=$(tile_y "$LAT_MAX" "$z")   # note: bigger latitude = smaller Y
  y_end=$(tile_y "$LAT_MIN" "$z")

  count_this_zoom=$(( (x_end - x_start + 1) * (y_end - y_start + 1) ))
  echo "Zoom $z : ~$count_this_zoom tiles..."

  for (( x=x_start; x<=x_end; x++ )); do
    for (( y=y_start; y<=y_end; y++ )); do

      dir="tiles/$z/$x"
      file="$dir/$y.png"

      if [[ -f "$file" ]]; then
        skipped=$((skipped + 1))
        continue
      fi

      mkdir -p "$dir"
      url="https://api.maptiler.com/maps/streets-v2/${z}/${x}/${y}.png?key=${MAPTILER_KEY}"

      if curl -sS -f -A "$UA" -o "$file" "$url"; then
        saved=$((saved + 1))
      else
        echo "  WARNING: skip $z/$x/$y (download failed)"
        rm -f "$file"   # don't leave a 0-byte file behind on failure
      fi

      sleep 0.12   # be polite to the free tile server
    done
  done
done

echo ""
echo "Done. $saved new tiles saved, $skipped already had, in ./tiles"
echo "You can now open index.html with no internet."