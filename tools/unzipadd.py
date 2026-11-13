#!/usr/bin/env python3
"""Undo `lpatch zipadd`: recover the stock APK and classes.dex from a Leafia-built APK.

usage: unzipadd.py <leafia.apk> <out stock.apk> <out classes.dex>

lpatch zipadd copies the stock APK up to its central directory, appends a stored
classes.dex entry, then the old central directory plus one entry and a new end
record. This takes exactly that apart, refusing anything else, so the stock APK
comes out byte for byte (check it against the car's stock md5 in
packages/aa-ev-model/cars). Used for the sandbox test and to predict the payload APK
md5; the head unit itself uses Leafia's own backup of the stock APK.
"""
import struct
import sys
import zlib

NAME = b"classes.dex"


def split(apk: bytes):
    e = apk.rfind(b"PK\x05\x06")
    if e < 0:
        raise SystemExit("no end of central directory")
    cnt, cdsize, cdoff, clen = (struct.unpack_from("<H", apk, e + 10)[0],
                                struct.unpack_from("<I", apk, e + 12)[0],
                                struct.unpack_from("<I", apk, e + 16)[0],
                                struct.unpack_from("<H", apk, e + 20)[0])
    if cdoff + cdsize != e or e + 22 + clen != len(apk):
        raise SystemExit("unsupported layout")
    # the last central entry must be zipadd's classes.dex
    last = cdoff + cdsize - (46 + len(NAME))
    if apk[last:last + 4] != b"PK\x01\x02" or apk[last + 46:last + 46 + len(NAME)] != NAME:
        raise SystemExit("last entry is not zipadd's classes.dex")
    loc = struct.unpack_from("<I", apk, last + 42)[0]
    dlen = struct.unpack_from("<I", apk, last + 20)[0]
    crc = struct.unpack_from("<I", apk, last + 16)[0]
    if (apk[loc:loc + 4] != b"PK\x03\x04" or struct.unpack_from("<H", apk, loc + 8)[0] != 0
            or apk[loc + 30:loc + 30 + len(NAME)] != NAME):
        raise SystemExit("classes.dex local header is not zipadd's")
    dex = apk[loc + 30 + len(NAME):loc + 30 + len(NAME) + dlen]
    if zlib.crc32(dex) & 0xffffffff != crc:
        raise SystemExit("classes.dex crc mismatch")
    old_cd = apk[cdoff:last]
    if loc + 30 + len(NAME) + dlen != cdoff:
        raise SystemExit("classes.dex is not right before the central directory")
    eocd = bytearray(apk[e:e + 22])
    struct.pack_into("<HHII", eocd, 8, cnt - 1, cnt - 1, len(old_cd), loc)
    stock = apk[:loc] + old_cd + bytes(eocd) + apk[e + 22:]
    return stock, dex


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    apk = open(sys.argv[1], "rb").read()
    stock, dex = split(apk)
    open(sys.argv[2], "wb").write(stock)
    open(sys.argv[3], "wb").write(dex)


if __name__ == "__main__":
    main()
