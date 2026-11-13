#!/bin/sh
# Full build of the aa.ev.model deliverables from the pristine base files:
#   1. patch the AA receiver library      -> dist/libautoreceiver_infobank.so
#   2. build the energy-model template    -> dist/ev_batch.bin + EvModelTemplate.java
#   3. compile the GPM sender classes     -> gpm-ev/build/smali
#   4. patch the GPM smali tree           -> build/gpm-smali
#   5. assemble classes.dex             -> dist/HKMC_GPM.classes.dex
#   6. build the NEMESIS package (deltas) -> dist/aa.ev.model.zip
#
# Requires: ~/tools/env.sh (Android SDK), smali/baksmali, capstone and bsdiff4
# in PY (e.g. /tmp/opencode/ev-venv/bin/python), qemu-arm-static (runs the
# shipped ARM lpatch), zip, protoc for checks.
set -e
cd "$(dirname "$0")/.."
PY="${PY:-/tmp/opencode/ev-venv/bin/python}"
LPATCH="${LPATCH:-qemu-arm-static third_party/lpatch/lpatch}"
export PY LPATCH
. "$HOME/tools/env.sh"

B=private/car-current-leafia105
if [ ! -s "$B/libautoreceiver_infobank.so" ]; then
    # Leafia v1.0.5's library is the same file NEMESIS's projection-tbt ships
    mkdir -p "$B"
    cp "${NEMESIS_REPO:-../hmg_nemesis}/Sources/packages/projection-tbt/files/libautoreceiver_infobank.so" "$B/"
fi

echo "== 1. library patch =="
"$PY" tools/patch_library.py

echo "== 2. energy model template =="
"$PY" tools/build_ioniq5_model.py   # Ioniq 5 values; Ford path: build_model_template.py
protoc -I reference --decode=vem.VehicleEnergyModel vehicle_energy_model.proto \
    < dist/ev_model.bin > /dev/null   # parse check

echo "== 3. compile sender classes =="
sh gpm-ev/build.sh

echo "== 4. patch GPM smali =="
# Leafia v1.0.5's GPM code is the same classes.dex on every car in
# packages/aa-ev-model/cars (md5 6124a666...): take it from that car's Leafia
# HKMC_GPM.apk (the live one, e.g. from Leafia's port kit), once.
# Without car files, both are rebuilt from public data: the library is the
# file NEMESIS's projection-tbt ships, and the code comes from Leafia's git
# history plus that package's GPM (tools/reconstruct_leafia_dex.py). Set
# LEAFIA_REPO / NEMESIS_REPO to checkouts of HMG-Leafia-Plus and hmg_nemesis.
B=private/car-current-leafia105
mkdir -p "$B"
if [ ! -s "$B/classes.dex" ]; then
    if [ -s "$B/HKMC_GPM.apk" ]; then
        unzip -p "$B/HKMC_GPM.apk" classes.dex > "$B/classes.dex"
    else
        "$PY" -I tools/reconstruct_leafia_dex.py "${LEAFIA_REPO:-../HMG-Leafia-Plus}" \
            "${NEMESIS_REPO:-../hmg_nemesis}" "$B/classes.dex"
    fi
fi
if [ ! -s "$B/libautoreceiver_infobank.so" ]; then
    cp "${NEMESIS_REPO:-../hmg_nemesis}/Sources/packages/projection-tbt/files/libautoreceiver_infobank.so" "$B/"
fi
[ "$(md5sum < "$B/classes.dex" | cut -d' ' -f1)" = 6124a666b2ae11883e91de85c19389d2 ] ||
    { echo "$B/classes.dex is not Leafia v1.0.5's GPM code" >&2; exit 1; }
if [ ! -d "$B/smali-gpm" ]; then
    baksmali d "$B/classes.dex" -o "$B/smali-gpm"
fi
"$PY" tools/patch_gpm_smali.py

echo "== 5. assemble dex =="
# The APK is assembled on the head unit (lpatch zipadd onto the car's own
# stock APK from Leafia's backup), so only the dex is built here.
smali a -j 1 --api 18 -o dist/HKMC_GPM.classes.dex build/gpm-smali

echo "== 6. NEMESIS package =="
sh packages/aa-ev-model/build.sh

echo
echo "built:"
md5sum dist/libautoreceiver_infobank.so dist/HKMC_GPM.classes.dex dist/aa.ev.model.zip
echo
echo "verify the package scripts: bash tools/test_package.sh"
