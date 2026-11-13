#!/bin/sh
# Build dist/aa.ev.model.zip from the payloads in dist/ (see tools/build_all.sh).
#
# The package carries no Hyundai/Google binaries: only lpatch deltas that
# rebuild our payloads on the head unit from its own files, plus lpatch itself
# (GPL-3.0, from HMG Leafia Plus; third_party/lpatch) and Leafia's own GPM
# deltas (third_party/leafia-gpm). One package fits every car in `cars`:
#   files/cars                             the cars and their Leafia/stock md5s
#   files/leafia/<set>.HKMC_GPM.tbt.lpd    stock odex -> Leafia's classes.dex
#   files/classes.dex.lpd                  Leafia's classes.dex -> ours
#   files/libautoreceiver_infobank.so.lpd  Leafia library -> ours
#   files/MD5SUMS                          md5 of Leafia's dex, our dex, our library
# Each delta is checked here by rebuilding its target with the real lpatch.
#
# Inputs: dist/HKMC_GPM.classes.dex, dist/libautoreceiver_infobank.so (ours),
# private/car-current-leafia105/{classes.dex,libautoreceiver_infobank.so}
# (Leafia v1.0.5's, from any car in `cars`: the same bytes on all of them).
# Env: PY (python with bsdiff4), LPATCH (host command for the ARM lpatch).
set -e
cd "$(dirname "$0")/../.."
PY="${PY:-python3}"
LPATCH="${LPATCH:-qemu-arm-static third_party/lpatch/lpatch}"
BASE=private/car-current-leafia105
F=packages/aa-ev-model/files
LEAFIA_DEX_MD5=6124a666b2ae11883e91de85c19389d2
LEAFIA_LIB_MD5=c08410a8d32a615b1aa805cd8a243d52

for f in dist/HKMC_GPM.classes.dex dist/libautoreceiver_infobank.so \
         "$BASE/classes.dex" "$BASE/libautoreceiver_infobank.so" third_party/lpatch/lpatch \
         third_party/leafia-gpm/ev6.HKMC_GPM.tbt.lpd third_party/leafia-gpm/neev.HKMC_GPM.tbt.lpd; do
    [ -s "$f" ] || { echo "missing $f" >&2; exit 1; }
done
[ "$(md5sum < "$BASE/classes.dex" | cut -d' ' -f1)" = "$LEAFIA_DEX_MD5" ] ||
    { echo "$BASE/classes.dex is not Leafia v1.0.5's GPM code" >&2; exit 1; }
[ "$(md5sum < "$BASE/libautoreceiver_infobank.so" | cut -d' ' -f1)" = "$LEAFIA_LIB_MD5" ] ||
    { echo "$BASE/libautoreceiver_infobank.so is not Leafia v1.0.5's library" >&2; exit 1; }

rm -rf "$F"
mkdir -p "$F/leafia"
delta() {  # <source> <target> <out.lpd>
    "$PY" -I third_party/lpatch/mkdelta.py "$1" "$2" "$3"
    rm -f "$3.check"
    $LPATCH delta "$3" "$1" "$3.check" >/dev/null
    cmp "$3.check" "$2" || { echo "delta $3 does not rebuild $2" >&2; exit 1; }
    rm -f "$3.check"
}
delta "$BASE/classes.dex" dist/HKMC_GPM.classes.dex "$F/classes.dex.lpd"
delta "$BASE/libautoreceiver_infobank.so" dist/libautoreceiver_infobank.so "$F/libautoreceiver_infobank.so.lpd"
cp -f third_party/leafia-gpm/ev6.HKMC_GPM.tbt.lpd third_party/leafia-gpm/neev.HKMC_GPM.tbt.lpd "$F/leafia/"
grep -v '^#' packages/aa-ev-model/cars | grep . > "$F/cars"
cp -f third_party/lpatch/lpatch "$F/lpatch"
chmod 755 "$F/lpatch"
{
    echo "$LEAFIA_DEX_MD5  leafia.dex"
    echo "$(md5sum < dist/HKMC_GPM.classes.dex | cut -d' ' -f1)  classes.dex"
    echo "$(md5sum < dist/libautoreceiver_infobank.so | cut -d' ' -f1)  libautoreceiver_infobank.so"
} > "$F/MD5SUMS"

out=dist/aa.ev.model.zip
rm -f "$out"
( cd packages/aa-ev-model && zip -q -r -D "$OLDPWD/$out" NEMESIS.data bin files scripts svc )
echo "built $out"
md5sum "$out"
