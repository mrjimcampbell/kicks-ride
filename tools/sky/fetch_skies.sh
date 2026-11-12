#!/bin/zsh
# Fetch the test-rig skies from Poly Haven (CC0) into assets/sky/build/ (gitignored; copied into
# the TV app by a build phase). Per preset: a 1K .hdr for image-based lighting, and the
# tonemapped panorama (max 8192 px wide) as the visible backdrop.
set -e
cd "${0:A:h}/../.."
OUT=assets/sky/build
mkdir -p $OUT
# preset id → Poly Haven asset (keep in sync with SkyPreset in KicksRideTV/SkyRig.swift)
typeset -A SKIES=(
  midday   kloofendal_48d_partly_cloudy_puresky
  morning  autumn_field_puresky
  golden   evening_road_01_puresky
  dusk     belfast_sunset_puresky
  overcast overcast_soil_puresky
  night    kloppenheim_02
)
for id asset in ${(kv)SKIES}; do
  [[ -f $OUT/sky_$id.hdr && -f $OUT/sky_$id.jpg ]] && { echo "$id: have it"; continue; }
  json=$(curl -sf https://api.polyhaven.com/files/$asset)
  hdr=$(print -r -- $json | python3 -c 'import json,sys; print(json.load(sys.stdin)["hdri"]["1k"]["hdr"]["url"])')
  jpg=$(print -r -- $json | python3 -c 'import json,sys; print(json.load(sys.stdin)["tonemapped"]["url"])')
  curl -sfL -o $OUT/sky_$id.hdr "$hdr"
  curl -sfL -o $OUT/sky_$id.full.jpg "$jpg"
  sips -Z 8192 $OUT/sky_$id.full.jpg --out $OUT/sky_$id.jpg >/dev/null && rm $OUT/sky_$id.full.jpg
  echo "$id: $asset"
done
