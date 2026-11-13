# Download

**[egmp-aa-ev-leafia-v0.3.0-ev6-usb.zip](egmp-aa-ev-leafia-v0.3.0-ev6-usb.zip)**: the USB installer for NEMESIS. Not yet tested on a car. Checksum: [SHA256SUMS](SHA256SUMS).

Needs: Kia EV6 US (260507) or Canada (260206), or Hyundai Ioniq 5 US (260507), with NEMESIS and HMG Leafia Plus v1.0.5 in full mode (with turn-by-turn). No HMG-API.

## Install
1. Download the zip (open it above, then **Download raw file**).
2. Unzip it onto an **empty** FAT32/exFAT USB drive. The top of the drive should then hold `NEMESIS.data`, `README.txt` and a `packages` folder. Don't unzip `packages/aa.ev.model.zip`.
3. Car on, head unit fully started: plug in the drive and tap **Yes** in NEMESIS.
4. The head unit restarts by itself. Remove the drive while it restarts.

If anything doesn't match exactly, a "not installed" pop-up appears and nothing is changed; the reason is in `/data/nemesis/aa.ev.model.log` (also in NEMESIS Manager's `aa.ev.model` entry).

## Uninstall
NEMESIS Manager (press NAV three times) → `aa.ev.model` → uninstall, then reboot. Leafia's files are restored byte for byte. Uninstall this before updating or removing Leafia.

The zip holds no Hyundai, Kia or Google files: install scripts, small patch files and `lpatch`, which rebuild the changed files on the head unit from its own.
