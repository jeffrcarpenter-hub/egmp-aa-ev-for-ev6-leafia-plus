#!/system/bin/sh
. /data/nemesis/apps/aa.ev.model/scripts/common.sh

log "postinstall aa.ev.model"
trap '[ $? = 0 ] || { sys_ro; apps_release; }' EXIT

# payloads rebuilt by preinstall: check them again before touching /system
load_car || { log "FAIL: car not listed"; exit 1; }
_pay_apk=$(payload_built_sum)
[ -n "$_pay_apk" ] || { log "FAIL: no payload checksum"; exit 1; }
sum_is "$PAYLOAD/HKMC_GPM.apk" "$_pay_apk" || exit 1
sum_is "$PAYLOAD/libautoreceiver_infobank.so" "$(manifest_sum libautoreceiver_infobank.so)" || exit 1

apps_hold
snapshot_all || exit 1
echo "$_pay_apk" > "$PAY_APK_SUM_FILE" || { log "FAIL: could not record the payload checksum"; exit 1; }
if ! sys_rw; then
    log "FAIL: remount /system rw"
    exit 1
fi

if ! put_lib "$PAYLOAD/HKMC_GPM.apk" "$GPM_APK"; then
    log "FAIL: install $GPM_APK"
    exit 1
fi
log "OK: $GPM_APK replaced"

rm -f "$GPM_ODEX" 2>/dev/null || true
if [ -f "$GPM_ODEX" ]; then
    log "FAIL: could not delete $GPM_ODEX"
    exit 1
fi
if ! write_odex "$GPM_APK" "$GPM_ODEX"; then
    rm -f "$GPM_ODEX" 2>/dev/null || true
    log "dexopt failed for HKMC_GPM; boot will optimize"
fi

if ! put_lib "$PAYLOAD/libautoreceiver_infobank.so" "$LIB_LIVE"; then
    log "FAIL: install $LIB_LIVE"
    exit 1
fi
log "OK: $LIB_LIVE replaced"

wipe_dalvik
prefill_dalvik "$GPM_ODEX"

sys_ro
apps_release
clean_payload
sync
log "off switch: setprop $OFF_PROP 1 (stock behaviour), back with setprop $OFF_PROP 0"

# The running GPM keeps the old code mapped until it restarts: reboot, as
# Leafia does.
retire_usb_descriptor
toast "AA EV model installed. Restarting now: remove the USB drive while it restarts."
log "done - rebooting"
sleep 3
exec /system/bin/reboot
log "FAIL: reboot returned - reboot the head unit by hand"
exit 0
