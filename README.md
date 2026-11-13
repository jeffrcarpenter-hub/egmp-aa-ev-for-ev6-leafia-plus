# egmp-aa-ev-feat

Real EV routing in Google Maps on Android Auto for E-GMP cars with a Gen5W head unit and HMG Leafia Plus (Hyundai Ioniq 5, Kia EV6): battery % on arrival, charging stops, realistic charge times, and automatic battery preconditioning on the way to a fast charger. Built on [NEMESIS](https://github.com/xwtk/hmg_nemesis) and [HMG Leafia Plus](https://github.com/VysseCodes/HMG-Leafia-Plus).

> [!WARNING]
> This modifies your infotainment system's files. The installer checks every file first and keeps a byte-for-byte backup, but you use it at your own risk. Not affiliated with Hyundai, Kia or Google.

## Requirements

- One of these cars, on the firmware HMG Leafia Plus supports in full mode (`packages/aa-ev-model/cars`):

  | Car | Firmware | Status |
  |---|---|---|
  | Hyundai Ioniq 5 US (2022, 2023) | `NEEV.USA` / `NEEV23.USA` 260507 | verified on a car (original package) |
  | Kia EV6 US | `CVEV.USA` 260507 | not yet tested on a car |
  | Kia EV6 Canada | `CVEV.CAN` 260206 | not yet tested on a car |

  Not supported: Ioniq 5 Canada (its Android Auto library differs), Ioniq 6 and any car Leafia runs only in basic mode (no turn-by-turn, which preconditioning needs).
- [NEMESIS](https://github.com/xwtk/hmg_nemesis) installed
- **[HMG Leafia Plus](https://github.com/VysseCodes/HMG-Leafia-Plus) v1.0.5 installed first, in full mode.** This package builds on Leafia's modified Android Auto files and rebuilds its own from Leafia's backup of the stock GPM; with anything else the installer refuses and changes nothing. HMG-API is not needed (and not supported).

### How one package fits every car

Leafia v1.0.5's Android Auto app code (`HKMC_GPM` `classes.dex`) is byte-identical on the Ioniq 5 and EV6; only the APK wrapper differs per car, and the Android Auto library is the same file on all of them. So the package ships one set of deltas, and on the head unit rebuilds Leafia's code from the stock GPM in Leafia's own backup (with Leafia's own delta), checks that this gives exactly the live Leafia APK, turns it into ours and wraps it in the car's own stock APK.

The car-side numbers (binder transactions and HEV flags for battery data and preconditioning) are defined by each car's framework, which differs between models. They're used as before on the Ioniq 5 framework they were verified on; on any other car they're used only if the car's framework names exactly those numbers (`IHEVService$Stub.TRANSACTION_setBattCondEvStation` and so on, `CarIds.java`), otherwise that feature stays off and the log says why.

## Features

- **EV routing:** the head unit sends Maps a vehicle energy model with the battery's live energy, so Maps plans stops and shows arrival %.
- **Maps' battery % matches the dash:** the head unit also sends Maps how the car's battery % relates to the battery's energy (Android Auto sensor 26). On E-GMP the energy runs out at about 2 % on the dash, so without it Maps' percentages (now, on arrival, at charging stops) read up to 2 points low near empty. From [AwsomeFox/egmp-aa-ev-hmg-api](https://github.com/AwsomeFox/egmp-aa-ev-hmg-api) (`SocCurve.java`), without HMG-API.
- **Live battery data for phone apps:** the battery %, the range the cluster shows and the odometer go to the phone as Android Auto's fuel and odometer data, so apps that read the car through Android Auto (A Better Route Planner, for one) show the live battery level. Also from AwsomeFox's project (`LiveData.java`).
- **Real capacity:** usable capacity is learned from the BMS, not assumed from the new-car 77.4 kWh.
- **Cold weather:** live outside temperature raises heating and rolling losses in the model.
- **Charge times:** calibrated on real DC sessions and the car's own estimate, including the slow last 10–20 %.
- **Preconditioning:** when the next stop is a charger over 50 kW within an hour, the car is asked to warm the battery. Turn it off with the car's own *battery conditioning* setting.
- **EV6:** the EV6 uses the Ioniq 5 model (the same 77.4 kWh E-GMP pack and 800 V charging); its usable capacity is learned from the BMS, so the charge curve and tables scale to it. Its road load is a little lower than the Ioniq 5's, so arrival % should be slightly conservative until EV6 logs tune it.
- **EV logs:** driving and charging, whenever the head unit is on; copied to any USB drive with an `egmp-aa-ev-logs` folder; share them through an [EV log issue](https://github.com/willemcvu/egmp-aa-ev-feat/issues/new?template=log-submission.yml).

## Install

1. Download the `-usb.zip` from [Releases](../../releases) and copy its **contents** to an empty FAT32/exFAT drive.
2. Car on, plug the drive into a USB data port, tap **Yes** when NEMESIS asks. The head unit restarts when it's done.

It upgrades earlier versions in place (an Ioniq 5 running the original package included). To uninstall: NEMESIS Manager (press NAV three times) → `aa.ev.model` → uninstall, then reboot; Leafia's files are restored exactly. Uninstall this before updating Leafia. More in the release's [README.txt](release/README.txt).

The release contains no Hyundai or Google files, only small binary deltas that [`lpatch`](third_party/lpatch) applies to your unit's own files.

## EV logs

The head unit records a small log whenever the car is on, driving or charging: battery energy and power, speed, temperatures, climate, charging and Maps' route plan. No location, no full VIN, no times of day. It keeps up to 100 MB, oldest first out.

To collect and share them:

1. Make a folder named `egmp-aa-ev-logs` at the top level of any FAT32/exFAT USB drive.
2. With the car on, plug the drive into the USB data port. Within about 20 seconds a pop-up says how many logs were copied ("… Safe to remove").
3. Open an [EV log issue](https://github.com/willemcvu/egmp-aa-ev-feat/issues/new?template=log-submission.yml) and drag the `egmp-*.csv` files from that folder into it. Issues are public.

Logs from different cars, climates and battery ages are what improve the energy model most. Format details: [LOGGING](docs/LOGGING.md).

## Docs

| | |
|---|---|
| [ENERGY-MODEL](docs/ENERGY-MODEL.md) | the energy model and its calibration |
| [PRECONDITIONING](docs/PRECONDITIONING.md) | how preconditioning works |
| [LOGGING](docs/LOGGING.md) | EV log format and `tools/evlog.py` |
| [DATA-SOURCES](docs/DATA-SOURCES.md) | vehicle data the head unit exposes |
| [RESEARCH](docs/RESEARCH.md) | head unit internals and the patch design |
| [HANDOFF](docs/HANDOFF.md) | developer guide: build, install, troubleshooting |
| [ROADMAP](docs/ROADMAP.md) | what's next |

## Building

The build patches files from your own head unit (not in this repo); see [HANDOFF](docs/HANDOFF.md) for what goes in `private/` and the toolchain.

```sh
PY=/path/to/python sh tools/build_all.sh   # build everything
sh gpm-ev/test/run.sh                      # Java host tests
bash tools/test_package.sh                 # package install/uninstall sandbox
sh tools/test_evlog.sh                     # EV log tools
sh tools/build_release.sh v0.2.0           # USB release zip
```

## Credits

`SocCurve.java`, `LiveData.java` and their tests come from [AwsomeFox/egmp-aa-ev-hmg-api](https://github.com/AwsomeFox/egmp-aa-ev-hmg-api) (AGPL-3.0), wired up here without HMG-API.

[NEMESIS](https://github.com/xwtk/hmg_nemesis) (xwtk), [HMG Leafia Plus](https://github.com/VysseCodes/HMG-Leafia-Plus) (including `lpatch`, GPL-3.0), [aa-proxy-rs](https://github.com/aa-proxy/aa-proxy-rs), [open-android-auto](https://github.com/mrmees/open-android-auto), [gen5w-preconditioning](https://github.com/paytondevs/gen5w-preconditioning).
