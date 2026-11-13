#!/usr/bin/env python3
"""Make a stand-in car for tools/test_package.sh: no Hyundai/Kia/Google bytes.

usage: make_test_car.py <out dir> <ro.build.product prefix> <seed>

Writes, in <out dir>:
  stock/HKMC_GPM.apk, stock/HKMC_GPM.odex   the "stock" GPM in Leafia's backup
  leafia/classes.dex, leafia/libautoreceiver_infobank.so  Leafia's code and library
  ours/classes.dex, ours/libautoreceiver_infobank.so      this package's
  files/leafia/test.HKMC_GPM.tbt.lpd   stock odex -> Leafia dex (like Leafia's)
  files/classes.dex.lpd, files/libautoreceiver_infobank.so.lpd, files/MD5SUMS
  car.partial   a files/cars line without the Leafia APK md5 (test_package.sh
                builds Leafia's APK with the real lpatch zipadd and fills it in)

The leafia dex is shared by every seed, as on the real cars (one classes.dex,
different APK wrappers); the stock APK and odex differ per seed.
"""
import hashlib
import io
import os
import random
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MKDELTA = os.path.join(ROOT, "third_party/lpatch/mkdelta.py")


def md5(b):
    return hashlib.md5(b).hexdigest()


def blob(seed, n):
    r = random.Random(seed)
    return bytes(r.getrandbits(8) for _ in range(n))


def put(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def delta(src, dst, out):
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run([sys.executable, "-I", MKDELTA, src, dst, out], check=True,
                   stdout=subprocess.DEVNULL)


def main():
    out, prefix, seed = sys.argv[1], sys.argv[2], sys.argv[3]
    # stock APK: a zip without classes.dex (stock GPM is odexed)
    b = io.BytesIO()
    with zipfile.ZipFile(b, "w") as z:
        z.writestr("AndroidManifest.xml", b"manifest-" + seed.encode() * 50)
        z.writestr("res/raw/x.bin", blob("res" + seed, 4000))
    stock_apk = b.getvalue()
    stock_odex = b"dey\n036\0" + blob("odex" + seed, 30000)
    leafia_dex = b"dex\n035\0" + blob("leafia-dex", 30000)
    ours_dex = leafia_dex[:20000] + b"EV PATCH" + leafia_dex[20000:] + blob("ours", 500)
    leafia_lib = b"\x7fELF" + blob("leafia-lib", 20000)
    ours_lib = leafia_lib[:9000] + b"\x00\x01" + leafia_lib[9002:]

    p = lambda *a: os.path.join(out, *a)
    put(p("stock/HKMC_GPM.apk"), stock_apk)
    put(p("stock/HKMC_GPM.odex"), stock_odex)
    put(p("leafia/classes.dex"), leafia_dex)
    put(p("leafia/libautoreceiver_infobank.so"), leafia_lib)
    put(p("ours/classes.dex"), ours_dex)
    put(p("ours/libautoreceiver_infobank.so"), ours_lib)
    delta(p("stock/HKMC_GPM.odex"), p("leafia/classes.dex"), p("files/leafia/test.HKMC_GPM.tbt.lpd"))
    delta(p("leafia/classes.dex"), p("ours/classes.dex"), p("files/classes.dex.lpd"))
    delta(p("leafia/libautoreceiver_infobank.so"), p("ours/libautoreceiver_infobank.so"),
          p("files/libautoreceiver_infobank.so.lpd"))
    put(p("files/MD5SUMS"), (
        "%s  leafia.dex\n%s  classes.dex\n%s  libautoreceiver_infobank.so\n"
        % (md5(leafia_dex), md5(ours_dex), md5(ours_lib))).encode())
    # <prefix> <set> <LEAFIA_APK> <leafia lib> <stock apk> <stock odex> <name>
    put(p("car.partial"), ("%s test LEAFIA_APK %s %s %s Test car %s\n"
                           % (prefix, md5(leafia_lib), md5(stock_apk), md5(stock_odex),
                              seed)).encode())


if __name__ == "__main__":
    main()
