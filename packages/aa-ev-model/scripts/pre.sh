#!/system/bin/sh
# NEMESIS runs preinstall from the staging dir, before the tree is copied to
# /data/nemesis/apps/aa.ev.model: source relatively and use the staged files.
FILES=./files
. ./scripts/common.sh

log "preinstall aa.ev.model"
trap '[ $? = 0 ] || clean_payload' EXIT
if [ ! -x /system/xbin/nemesis ]; then
    log "FAIL: /system/xbin/nemesis missing"
    exit 1
fi

for _f in MD5SUMS cars lpatch classes.dex.lpd libautoreceiver_infobank.so.lpd; do
    if [ ! -s "$FILES/$_f" ]; then
        log "FAIL: $FILES/$_f missing"
        exit 1
    fi
done
SUM_PAY_LIB=$(manifest_sum libautoreceiver_infobank.so) || { log "FAIL: no manifest entry for libautoreceiver_infobank.so"; exit 1; }

if ! load_car; then
    log "FAIL: $(getprop ro.build.product) is not a car this package supports - refusing"
    toast "AA EV model not installed: this car isn't supported (Ioniq 5 US, Kia EV6 US/Canada with HMG Leafia Plus v1.0.5). Nothing was changed."
    exit 1
fi
log "car: $CAR_NAME ($(getprop ro.build.product), Leafia set $LEAFIA_SET)"
if [ ! -s "$FILES/leafia/$LEAFIA_SET.HKMC_GPM.tbt.lpd" ]; then
    log "FAIL: $FILES/leafia/$LEAFIA_SET.HKMC_GPM.tbt.lpd missing"
    exit 1
fi

# Live files must be either Leafia v1.0.5's for this car (fresh install) or ours
# with a verified Leafia snapshot (reinstall, or upgrade from an earlier build:
# our library is unchanged between builds, the GPM APK is not).
_live_apk=$(file_md5 "$GPM_APK")
_live_lib=$(file_md5 "$LIB_LIVE")
log "live: apk=$_live_apk lib=$_live_lib"

if [ "$_live_apk:$_live_lib" = "$SUM_BASE_APK:$SUM_BASE_LIB" ]; then
    log "live files are Leafia v1.0.5's - ok"
    _src_lib=$LIB_LIVE
elif [ "$_live_lib" = "$SUM_PAY_LIB" ] && [ "$_live_apk" != "$SUM_BASE_APK" ]; then
    # already ours: only safe with a complete Leafia snapshot to fall back to
    if snapshot_is_base; then
        log "live files are this package's - reinstalling over them"
        _src_lib=$BACKUP_DIR/libautoreceiver_infobank.so
    else
        log "FAIL: live files are ours but there is no valid Leafia snapshot to uninstall to"
        toast "AA EV model not installed: no Leafia backup found. Uninstall aa.ev.model, reboot, and try again."
        exit 1
    fi
else
    log "FAIL: live files are neither Leafia v1.0.5's for $CAR_NAME nor this package's - refusing"
    toast "AA EV model not installed: needs HMG Leafia Plus v1.0.5 (full mode) on this car. Nothing was changed."
    exit 1
fi

if ! build_payloads "$_src_lib"; then
    toast "AA EV model not installed: could not rebuild its files from this head unit's. Nothing was changed."
    exit 1
fi

log "preinstall ok"
exit 0
