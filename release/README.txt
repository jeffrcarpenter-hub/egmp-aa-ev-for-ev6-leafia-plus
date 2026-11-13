EV routing for Android Auto - aa.ev.model @VERSION@
https://github.com/jeffrcarpenter-hub/egmp-aa-ev-without-the-bullshit   (built from commit @COMMIT@)
Based on https://github.com/willemcvu/egmp-aa-ev-feat. No HMG-API.

Makes Google Maps on Android Auto treat the car as an EV:
- battery % on arrival, charging stops, charge times and range, from the
  battery's live energy and its real (learned) usable capacity, with a
  cold-weather model driven by the live outside temperature;
- Maps' battery % matches the car's own (dash) battery %;
- live battery %, range and odometer for phone apps that read the car
  through Android Auto (A Better Route Planner and others);
- battery preconditioning: when the next stop on the Maps route is a fast
  charger (over 50 kW) at most 60 minutes away, the car is asked to warm
  the battery, the same way its own navigation does. Always on. To turn it
  off, switch off "battery conditioning" in the car's EV settings;
- EV logs: one small file each time the head unit is on, driving or
  charging (battery, speed, temperatures, climate, charging, model values;
  no location, no full VIN, no times of day), copied to a USB
  drive that has a folder named egmp-aa-ev-logs. Share them by opening an
  "EV log submission" issue on the GitHub page above.

WARNING: this modifies the infotainment system's files. It checks every file
before changing anything and keeps a backup for uninstall, but you use it at
your own risk.

REQUIREMENTS (the installer refuses anything else and changes nothing)
- One of these, Gen5W head unit:
    Kia EV6 (US), software CVEV.USA.0000.V015.012.260507   (not yet tested on a car)
    Kia EV6 (Canada), software CVEV.CAN.*.260206            (not yet tested on a car)
    Hyundai Ioniq 5 (US, 2022/2023), software NEEV.USA / NEEV23.USA 260507
- NEMESIS installed (https://github.com/xwtk/hmg_nemesis)
- HMG Leafia Plus v1.0.5 installed in full mode, i.e. with turn-by-turn
  (https://github.com/VysseCodes/HMG-Leafia-Plus). Not HMG-API.

INSTALL (also upgrades an earlier version in place)
1. Copy the CONTENTS of this zip to the root of an empty FAT32/exFAT USB
   drive. Don't unzip packages/aa.ev.model.zip. No other NEMESIS.data may be
   on the drive.
       NEMESIS.data
       packages/aa.ev.model.zip
       README.txt
2. Car on, head unit fully started, plug the drive into a USB data port.
3. NEMESIS asks whether to run the item on the drive: tap Yes.
4. Wait: after a few seconds it says it's installed and the head unit
   restarts by itself. Remove the drive while it restarts. (It renames
   NEMESIS.data on the drive to NEMESIS.data.installed so a drive left in
   doesn't install again; rename it back to reinstall.) If it refuses, a
   message says so, nothing is changed and it doesn't restart.
5. Plug in Android Auto (the first time after installing it can take an
   extra minute). In Google Maps, battery % shows on routes and long trips
   add charging stops.

EV LOGS
Make a folder named egmp-aa-ev-logs on a USB drive and plug it in after
driving or charging (the phone and the drive may share the one USB data
port). A
pop-up says how many logs were copied; then it's safe to remove.

UNINSTALL
NEMESIS Manager (press NAV three times) -> aa.ev.model -> uninstall, then
reboot. Leafia's original files are restored byte for byte. Uninstall this
BEFORE updating or uninstalling Leafia.

OFF SWITCH (keeps it installed, needs ADB)
  setprop persist.gpm.ev.off 1    then replug Android Auto (0 turns it back on)
Preconditioning has no switch here: use the car's battery conditioning setting.

TROUBLESHOOTING
- Log: /data/nemesis/aa.ev.model.log (also shown in NEMESIS Manager's
  aa.ev.model entry). Log copying: /data/nemesis/aa.ev.model.offload.log.
- "not installed" message: your car, head unit software or Leafia version
  isn't one this build is for, or Leafia's backup of the stock GPM app
  (/data/nemesis/backup/projection.tbt) is missing. Nothing was changed; the
  log says which.
- To check the car-side numbers on a car other than the Ioniq 5:
  adb logcat -s EvCar EvPrecond EvModelSender. "not the Ioniq 5 profile;
  numbers checked by name" is expected on an EV6; a line "... expected N;
  not using it on this car" means that feature is off on this car.
- Android Auto won't start after install: wait a minute after the first
  boot; if it still won't, uninstall as above.
- Wi-Fi shows an error after a restart: switch the car fully off and on.

WHAT'S IN THE PACKAGE
No Hyundai or Google files. packages/aa.ev.model.zip contains install
scripts, the log copy service, a car table, small patch files (deltas), and
lpatch plus Leafia's own GPM deltas from HMG Leafia Plus (GPL-3.0, in the
repo under third_party/). On the head unit, lpatch rebuilds Leafia's GPM
code from Leafia's backup of the stock app, checks it gives exactly your
live Leafia app, then builds the modified GPM app and Android Auto library
from them, and only if every file is byte-for-byte the expected one.
