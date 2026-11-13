#!/system/bin/sh
# aa.ev.model — advertise ELECTRIC + sensor 23 and send the energy model to AA.
#
# Cars: every E-GMP car HMG Leafia Plus v1.0.5 builds with the US Android Auto
# library (files/cars): Ioniq 5 US (NEEV, NEEV23), Kia EV6 US and Canada.
# Leafia's turn-by-turn GPM code (classes.dex) is byte-identical on all of
# them; only the APK wrapper differs. So one set of deltas fits every car:
#
# The package ships no Hyundai/Google binaries. files/ holds lpatch deltas
# (*.lpd) and lpatch itself; preinstall rebuilds the payloads into $PAYLOAD
# from the unit's own files (lpatch refuses any other source):
#   Leafia's stock GPM backup (odex) --Leafia's own .lpd--> Leafia's classes.dex
#   Leafia's classes.dex --files/classes.dex.lpd--> our classes.dex
#   Leafia's stock GPM backup (apk) + our classes.dex --lpatch zipadd--> our APK
#   Leafia's library --files/libautoreceiver_infobank.so.lpd--> our library
# As a self-check the same zipadd with Leafia's classes.dex must give exactly
# the live Leafia APK for this car (files/cars) before anything is used.
# Install gates on the live files being exactly Leafia v1.0.5's files for this
# car (or this package's own, with a verified Leafia snapshot, for a
# reinstall/upgrade), snapshots them, and swaps in the payloads. Uninstall restores the snapshot
# byte for byte, but only for files that are still ours (if Leafia was
# uninstalled in between, its files are not put back).
#
# Off switch without uninstall: setprop persist.gpm.ev.off 1 (and replug AA).

export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

PKG_DIR=/data/nemesis/apps/aa.ev.model
# preinstall runs from the staging dir before the tree exists at PKG_DIR;
# pre.sh sets FILES=./files before sourcing this file.
FILES=${FILES:-$PKG_DIR/files}
PAYLOAD=/data/nemesis/build/aa.ev.model
BACKUP_DIR=/data/nemesis/backup/aa.ev.model
LOG=/data/nemesis/aa.ev.model.log
HOLD_FILE=/data/nemesis/aa.ev.model.stopped
OFF_PROP=persist.gpm.ev.off

APP_DIR=/system/app
GPM_APK=$APP_DIR/HKMC_GPM.apk
GPM_ODEX=$APP_DIR/HKMC_GPM.odex
LIB_LIVE=/system/lib/libautoreceiver_infobank.so

# Leafia's turn-by-turn part keeps the stock GPM here while it's installed.
LEAFIA_BACKUP=/data/nemesis/backup/projection.tbt
# md5 of the payload APK this install built (it depends on the car's own stock
# APK, so it isn't in files/MD5SUMS); preuninstall and status read it.
PAY_APK_SUM_FILE=$BACKUP_DIR/payload-apk.md5

# Per car (files/cars, by ro.build.product prefix), set by load_car:
#   CAR_NAME, LEAFIA_SET (Leafia's patch set), SUM_BASE_APK / SUM_BASE_LIB
#   (Leafia v1.0.5's live files), SUM_STOCK_APK / SUM_STOCK_ODEX (the stock
#   GPM in Leafia's backup).
CAR_NAME=
LEAFIA_SET=
SUM_BASE_APK=
SUM_BASE_LIB=
SUM_STOCK_APK=
SUM_STOCK_ODEX=

GPM_PKG=com.google.android.projection.sink

log() {
    local _msg="$1"
    echo "$_msg"
    mkdir -p /data/nemesis 2>/dev/null || true
    echo "$_msg" >> "$LOG" 2>/dev/null || true
}

toast() {
    am broadcast -a com.hkmc.intent.action.TOAST \
        -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" \
        --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 || true
}

sys_rw() {
    /system/xbin/nemesis remount rw >/dev/null 2>&1
}

sys_ro() {
    /system/xbin/nemesis remount ro >/dev/null 2>&1 || true
}

file_md5() {
    local _line
    local _sum
    _line=$(md5 "$1" 2>/dev/null) || return 1
    set -- $_line
    _sum=$1
    [ -n "$_sum" ] || return 1
    echo "$_sum"
}

sum_is() {
    local _live="$1"
    local _want="$2"
    local _got
    if [ ! -s "$_live" ]; then
        log "FAIL: $_live missing"
        return 1
    fi
    _got=$(file_md5 "$_live") || {
        log "FAIL: md5 $_live"
        return 1
    }
    if [ "$_got" != "$_want" ]; then
        log "FAIL: $_live checksum $_got want $_want"
        return 1
    fi
    return 0
}

manifest_sum() {
    local _name="$1"
    local _line
    _line=$(grep "  $_name\$" "$FILES/MD5SUMS" 2>/dev/null) || return 1
    set -- $_line
    [ -n "$1" ] || return 1
    echo "$1"
}

chown_system() {
    chown 0.0 "$1" 2>/dev/null || chown 0:0 "$1" 2>/dev/null || true
}

# load_car: find this car in files/cars by ro.build.product; 1 if not listed.
# Line: <prefix> <leafia set> <leafia apk> <leafia lib> <stock apk> <stock odex> <name...>
load_car() {
    local _p _pre _set _apk _lib _sapk _sodex _name
    _p=$(getprop ro.build.product 2>/dev/null)
    [ -n "$_p" ] && [ -s "$FILES/cars" ] || return 1
    while read -r _pre _set _apk _lib _sapk _sodex _name; do
        case "$_pre" in ''|\#*) continue ;; esac
        case "$_p" in
            "$_pre"*)
                CAR_NAME=$_name
                LEAFIA_SET=$_set
                SUM_BASE_APK=$_apk
                SUM_BASE_LIB=$_lib
                SUM_STOCK_APK=$_sapk
                SUM_STOCK_ODEX=$_sodex
                return 0
                ;;
        esac
    done < "$FILES/cars"
    return 1
}

# the snapshot holds exactly Leafia v1.0.5's GPM APK and library for this car
# (and an odex: the one Leafia's install left, whatever its bytes)
snapshot_is_base() {
    [ "$(file_md5 "$BACKUP_DIR/HKMC_GPM.apk")" = "$SUM_BASE_APK" ] &&
    [ -s "$BACKUP_DIR/HKMC_GPM.odex" ] &&
    [ "$(file_md5 "$BACKUP_DIR/libautoreceiver_infobank.so")" = "$SUM_BASE_LIB" ]
}

# payload_apk_sum: md5 of the GPM APK this package installed ("" if unknown)
payload_apk_sum() {
    local _s
    [ -s "$PAY_APK_SUM_FILE" ] || return 0
    read -r _s < "$PAY_APK_SUM_FILE"
    echo "$_s"
}

# NEMESIS 1.15 force-updates an installed package from a USB drive left in at
# boot, so with the reboot after install a drive left in would reinstall and
# reboot forever. Rename our descriptor (as Leafia does) so the next boot
# leaves it alone.
retire_usb_descriptor() {
    local _d
    for _d in /storage/usb0 /storage/usb1 /storage/usb2 /mnt/media_rw/usb0 /mnt/media_rw/usb1 /mnt/media_rw/usb2; do
        [ -f "$_d/NEMESIS.data" ] || continue
        grep -q '^type=install' "$_d/NEMESIS.data" 2>/dev/null || continue
        grep -q 'aa\.ev\.model\.zip' "$_d/NEMESIS.data" 2>/dev/null || continue
        if mv "$_d/NEMESIS.data" "$_d/NEMESIS.data.installed" 2>/dev/null; then
            log "renamed $_d/NEMESIS.data to NEMESIS.data.installed so the next boot does not reinstall"
        else
            log "WARN: could not rename $_d/NEMESIS.data - remove the USB drive before the head unit restarts"
        fi
    done
    return 0
}

clean_payload() {
    case "$PAYLOAD" in
        */data/nemesis/build/aa.ev.model) rm -rf "$PAYLOAD"; rmdir "${PAYLOAD%/*}" 2>/dev/null ;;
    esac
    return 0
}

lp() {
    "$FILES/lpatch" "$@" >> "$LOG" 2>&1
}

# build_payloads <Leafia lib>: rebuild our payloads into $PAYLOAD from Leafia's
# stock GPM backup and the given Leafia library (live, or our snapshot on a
# reinstall). lpatch only writes a result when the source is the exact file
# the delta was made from; every fixed result must match files/MD5SUMS.
build_payloads() {
    local _sapk="$LEAFIA_BACKUP/HKMC_GPM.apk" _sodex="$LEAFIA_BACKUP/HKMC_GPM.odex"
    clean_payload
    mkdir -p "$PAYLOAD" || { log "FAIL: mkdir $PAYLOAD"; return 1; }
    chmod 755 "$FILES/lpatch" 2>/dev/null || true

    # Leafia's stock GPM backup must be the stock files Leafia built from
    sum_is "$_sapk" "$SUM_STOCK_APK" || { log "FAIL: Leafia's stock GPM backup is missing or not this car's"; return 1; }
    sum_is "$_sodex" "$SUM_STOCK_ODEX" || { log "FAIL: Leafia's stock GPM backup is missing or not this car's"; return 1; }

    # Leafia's classes.dex, rebuilt from the stock odex with Leafia's own delta
    if ! lp delta "$FILES/leafia/$LEAFIA_SET.HKMC_GPM.tbt.lpd" "$_sodex" "$PAYLOAD/leafia.dex"; then
        log "FAIL: could not rebuild Leafia's GPM code from $_sodex"
        return 1
    fi
    sum_is "$PAYLOAD/leafia.dex" "$(manifest_sum leafia.dex)" || return 1

    # self-check: stock APK + Leafia's code must be exactly the live Leafia APK
    if ! lp zipadd "$_sapk" "$PAYLOAD/leafia.dex" "$PAYLOAD/leafia.apk"; then
        log "FAIL: could not assemble Leafia's APK for the self-check"
        return 1
    fi
    sum_is "$PAYLOAD/leafia.apk" "$SUM_BASE_APK" || { log "FAIL: self-check: rebuilt Leafia APK differs"; return 1; }
    rm -f "$PAYLOAD/leafia.apk"

    # our classes.dex, then our APK
    if ! lp delta "$FILES/classes.dex.lpd" "$PAYLOAD/leafia.dex" "$PAYLOAD/classes.dex"; then
        log "FAIL: could not rebuild our GPM code"
        return 1
    fi
    sum_is "$PAYLOAD/classes.dex" "$(manifest_sum classes.dex)" || return 1
    if ! lp zipadd "$_sapk" "$PAYLOAD/classes.dex" "$PAYLOAD/HKMC_GPM.apk"; then
        log "FAIL: could not assemble our GPM APK"
        return 1
    fi
    rm -f "$PAYLOAD/leafia.dex" "$PAYLOAD/classes.dex"
    file_md5 "$PAYLOAD/HKMC_GPM.apk" > "$PAYLOAD/HKMC_GPM.apk.md5" || return 1

    # our library
    if ! lp delta "$FILES/libautoreceiver_infobank.so.lpd" "$1" "$PAYLOAD/libautoreceiver_infobank.so"; then
        log "FAIL: could not rebuild libautoreceiver_infobank.so from $1"
        return 1
    fi
    sum_is "$PAYLOAD/libautoreceiver_infobank.so" "$(manifest_sum libautoreceiver_infobank.so)" || return 1
    log "rebuilt payloads for $CAR_NAME (apk $(payload_built_sum))"
    return 0
}

payload_built_sum() {
    local _s
    read -r _s < "$PAYLOAD/HKMC_GPM.apk.md5" 2>/dev/null
    echo "$_s"
}

# copy beside the target, then rename over it (new inode; a running app keeps
# the old mapping until it restarts)
put_lib() {
    local _src="$1"
    local _dst="$2"
    local _tmp="${_dst}.evtmp"
    rm -f "$_tmp" 2>/dev/null || true
    cp -f "$_src" "$_tmp" || { rm -f "$_tmp" 2>/dev/null; return 1; }
    if ! cmp "$_src" "$_tmp" >/dev/null 2>&1; then
        rm -f "$_tmp" 2>/dev/null || true
        return 1
    fi
    chmod 644 "$_tmp" 2>/dev/null || true
    chown_system "$_tmp"
    mv "$_tmp" "$_dst" || { rm -f "$_tmp" 2>/dev/null; return 1; }
    chmod 644 "$_dst" 2>/dev/null || true
    chown_system "$_dst"
    if [ -x /system/bin/restorecon ]; then
        restorecon "$_dst" 2>/dev/null || true
    fi
    cmp "$_src" "$_dst" >/dev/null 2>&1
}

android_up() { [ "$(getprop sys.boot_completed 2>/dev/null)" = 1 ]; }

apps_hold() {
    android_up || return 0
    touch "$HOLD_FILE" 2>/dev/null || { log "WARN: cannot record stopped apps; not stopping them"; return 0; }
    if pm path "$GPM_PKG" >/dev/null 2>&1; then
        case " $(cat "$HOLD_FILE" 2>/dev/null) " in
            *" $GPM_PKG "*) ;;
            *) echo "$GPM_PKG" >> "$HOLD_FILE" ;;
        esac
        if pm disable "$GPM_PKG" >/dev/null 2>&1; then
            log "stopped $GPM_PKG for the file swap"
        else
            log "WARN: could not stop $GPM_PKG"
        fi
    fi
    return 0
}

apps_release() {
    [ -f "$HOLD_FILE" ] || return 0
    if ! android_up; then
        log "WARN: apps stopped by an earlier run stay stopped until this runs with Android up"
        return 0
    fi
    if pm enable "$GPM_PKG" >/dev/null 2>&1; then
        log "started $GPM_PKG again"
        rm -f "$HOLD_FILE"
    else
        log "WARN: could not start $GPM_PKG again"
    fi
    return 0
}

snapshot_all() {
    mkdir -p "$BACKUP_DIR" 2>/dev/null || true
    local _f _bak
    for _f in "$GPM_APK" "$GPM_ODEX" "$LIB_LIVE"; do
        _bak="$BACKUP_DIR/${_f##*/}"
        if [ -s "$_bak" ]; then
            log "snapshot exists for ${_f##*/} - keeping original"
        else
            if [ ! -s "$_f" ]; then
                log "FAIL: $_f missing, cannot snapshot"
                return 1
            fi
            cp -f "$_f" "$_bak" || return 1
            chmod 644 "$_bak" 2>/dev/null || true
            log "backed up $_f"
        fi
    done
    return 0
}

write_odex() {
    local _apk="$1"
    local _odex="$2"
    if [ -z "$BOOTCLASSPATH" ]; then
        export BOOTCLASSPATH=/system/framework/core.jar:/system/framework/conscrypt.jar:/system/framework/okhttp.jar:/system/framework/core-junit.jar:/system/framework/bouncycastle.jar:/system/framework/ext.jar:/system/framework/framework.jar:/system/framework/framework2.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/mms-common.jar:/system/framework/android.policy.jar:/system/framework/services.jar:/system/framework/apache-xml.jar:/system/framework/webviewchromium.jar:/system/framework/automotive.jar
    fi
    if [ ! -x /system/bin/dexopt ]; then
        log "dexopt binary missing"
        return 1
    fi
    log "dexopt $_apk"
    /system/bin/dexopt --preopt "$_apk" "$_odex" "m=y,u=n" || return 1
    [ -s "$_odex" ] || return 1
    chmod 644 "$_odex" 2>/dev/null || true
    chown_system "$_odex"
    if [ -x /system/bin/restorecon ]; then
        restorecon "$_odex" 2>/dev/null || true
    fi
    return 0
}

wipe_dalvik() {
    rm -f /data/dalvik-cache/*HKMC_GPM* 2>/dev/null || true
    rm -f /data/dalvik-cache/arm/*HKMC_GPM* 2>/dev/null || true
    rm -f /cache/dalvik-cache/*HKMC_GPM* 2>/dev/null || true
}

# The APK carries classes.dex, so PackageManager looks in the dalvik cache and
# re-optimises at boot if empty. Prefill it with the odex (same file).
prefill_dalvik() {
    local _odex="$1"
    local _cache="/data/dalvik-cache/system@app@HKMC_GPM.apk@classes.dex"
    [ -s "$_odex" ] || return 0
    [ -d /data/dalvik-cache ] || return 0
    rm -f "${_cache}.tmp" 2>/dev/null || true
    if ! cp -f "$_odex" "${_cache}.tmp" 2>/dev/null || ! cmp "$_odex" "${_cache}.tmp" >/dev/null 2>&1; then
        rm -f "${_cache}.tmp" 2>/dev/null || true
        log "dalvik cache not filled; boot will optimize"
        return 0
    fi
    chmod 644 "${_cache}.tmp" 2>/dev/null || true
    chown 1000:1000 "${_cache}.tmp" 2>/dev/null || chown 1000.1000 "${_cache}.tmp" 2>/dev/null || true
    mv "${_cache}.tmp" "$_cache" 2>/dev/null || { rm -f "${_cache}.tmp" 2>/dev/null; return 0; }
    if [ -x /system/bin/restorecon ]; then
        restorecon "$_cache" 2>/dev/null || true
    fi
    log "dalvik cache filled for HKMC_GPM.apk"
    return 0
}
