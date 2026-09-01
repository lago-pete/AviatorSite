# =====================================================================
#  setup-offline.ps1
#
#  Run this ONCE while you still have internet (from the AviatorSite
#  folder):   powershell -ExecutionPolicy Bypass -File .\setup-offline.ps1
#
#  It downloads two things so index.html works with NO internet later:
#    1. the Leaflet map library  ->  ./lib
#    2. map image tiles for your flight area  ->  ./tiles
#
#  Re-running it is safe: tiles that already exist are skipped.
# =====================================================================

param(
  # ---- bounding box of the area you want map coverage for (degrees) ----
  #      defaults cover the city of Chandler, AZ (plus a little margin)
  [double]$LatMin = 33.15,
  [double]$LatMax = 33.45,
  [double]$LonMin = -112.02,
  [double]$LonMax = -111.72,

  # ---- zoom levels to cache ----
  #      MUST match minZoom / maxZoom in index.html's tileLayer(...).
  #      Each extra zoom level roughly 4x's the tile count & download time.
  [int]$ZoomMin = 10,
  [int]$ZoomMax = 15
)

$ErrorActionPreference = "Stop"

# free tile servers want a real, identifiable User-Agent
$ua = "AviatorSite-offline-setup/1.0 (personal offline flight dashboard)"


# ---------------------------------------------------------------------
# 1. Leaflet library
# ---------------------------------------------------------------------
Write-Host "Downloading Leaflet library..."
New-Item -ItemType Directory -Force -Path "lib\images" | Out-Null

$base = "https://unpkg.com/leaflet@1.9.4/dist"
Invoke-WebRequest "$base/leaflet.js"  -OutFile "lib\leaflet.js"  -Headers @{ "User-Agent" = $ua } -UseBasicParsing
Invoke-WebRequest "$base/leaflet.css" -OutFile "lib\leaflet.css" -Headers @{ "User-Agent" = $ua } -UseBasicParsing

# marker/control images referenced by leaflet.css (not strictly needed for
# this dashboard, but grabbing them keeps the library self-contained)
foreach ($img in "marker-icon.png","marker-icon-2x.png","marker-shadow.png","layers.png","layers-2x.png") {
  try {
    Invoke-WebRequest "$base/images/$img" -OutFile "lib\images\$img" -Headers @{ "User-Agent" = $ua } -UseBasicParsing
  } catch {
    Write-Warning "could not fetch image $img (safe to ignore)"
  }
}
Write-Host "  -> saved to .\lib"


# ---------------------------------------------------------------------
# 2. Map tiles
# ---------------------------------------------------------------------
# standard slippy-map math: lon/lat + zoom  ->  tile x/y
function Get-TileX([double]$lon, [int]$z) {
  [math]::Floor((($lon + 180.0) / 360.0) * [math]::Pow(2, $z))
}
function Get-TileY([double]$lat, [int]$z) {
  $rad = $lat * [math]::PI / 180.0
  [math]::Floor((1.0 - [math]::Log([math]::Tan($rad) + (1.0 / [math]::Cos($rad))) / [math]::PI) / 2.0 * [math]::Pow(2, $z))
}

$servers = @("a", "b", "c")
$saved = 0
$skipped = 0

for ($z = $ZoomMin; $z -le $ZoomMax; $z++) {

  $xStart = Get-TileX $LonMin $z
  $xEnd   = Get-TileX $LonMax $z
  $yStart = Get-TileY $LatMax $z    # note: bigger latitude = smaller Y
  $yEnd   = Get-TileY $LatMin $z

  $countThisZoom = ($xEnd - $xStart + 1) * ($yEnd - $yStart + 1)
  Write-Host "Zoom $z : ~$countThisZoom tiles..."

  for ($x = $xStart; $x -le $xEnd; $x++) {
    for ($y = $yStart; $y -le $yEnd; $y++) {

      $dir  = "tiles\$z\$x"
      $file = "$dir\$y.png"

      if (Test-Path $file) { $skipped++; continue }

      New-Item -ItemType Directory -Force -Path $dir | Out-Null
      $s   = $servers[(Get-Random -Maximum $servers.Count)]
      $url = "https://$s.tile.openstreetmap.org/$z/$x/$y.png"

      try {
        Invoke-WebRequest $url -OutFile $file -Headers @{ "User-Agent" = $ua } -UseBasicParsing
        $saved++
      } catch {
        Write-Warning "skip $z/$x/$y  ($($_.Exception.Message))"
      }

      Start-Sleep -Milliseconds 120   # be polite to the free tile server
    }
  }
}

Write-Host ""
Write-Host "Done. $saved new tiles saved, $skipped already had, in .\tiles"
Write-Host "You can now open index.html with no internet."
