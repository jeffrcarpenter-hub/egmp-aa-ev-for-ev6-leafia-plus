#!/usr/bin/env python3
"""Rebuild Leafia v1.0.5's GPM classes.dex (md5 6124a666...) from public data only.

usage: reconstruct_leafia_dex.py <HMG-Leafia-Plus git checkout> <hmg_nemesis checkout> <out classes.dex>

No car needed. Inputs (both public):
  - NEMESIS projection-tbt HKMC_GPM.apk (Sources/packages/projection-tbt/files): its
    classes.dex (md5 20027f53...) is the target of Leafia's FIRST EV6 delta
    (commit 8240207, patches/ev6/HKMC_GPM.tbt.lpd: stock odex -> 20027f53).
  - Leafia's git history: that delta, the c78abf6 one (stock odex -> 9ba4a4fc) and
    the final 08f4436 one (stock odex -> 6124a666).

How:
  1. bsdiff: new[i] = old[j] + diff[i]. With the first delta's target known, solve
     the stock odex bytes it reads (about 64% of the odex).
  2. Apply the c78abf6 delta with those bytes: it comes out complete (md5-checked).
  3. Apply the final delta: every byte comes out except 30759, all in the class_defs
     and class_data tables (all code, strings, ids and the header are known).
     Leafia's last commits added one method (StartReceiver.leafiaNotPhone) and
     dropped two framework references; class order is unchanged.
  4. Rebuild class_defs and class_data from the c78abf6 version, remapped to the
     final ids, with code items assigned in smali's order (classes by type index,
     then each class's direct and virtual methods), and the one new method
     (private static). The result must match the delta's md5; it does.

Also prints and checks the md5s. Writes nothing unless the result is exact.
"""
import hashlib
import io
import struct
import subprocess
import sys
import zipfile
import zlib

FINAL_MD5 = "6124a666b2ae11883e91de85c19389d2"
NEMESIS_MD5 = "20027f539370c5d01594a33ccd74b331"
T3_MD5 = "9ba4a4fc68c9b9e5f87c862a31b632bc"
NEW_METHOD = ("Lcom/google/android/projection/service/StartReceiver;", "leafiaNotPhone",
              ("Z", ("Landroid/hardware/usb/UsbDevice;",)))
NEW_METHOD_ACCESS = 0x0a  # private static


# ---- lpatch deltas -------------------------------------------------------------

def parse_lpd(d):
    assert d[:4] == b"LPD1"
    slen = struct.unpack("<I", d[4:8])[0]
    comp, plen = struct.unpack("<II", d[44:52])
    body = zlib.decompress(d[52:52 + plen], -15) if comp == 1 else d[52:52 + plen]
    n = struct.unpack("<I", body[:4])[0]; p = 4
    ctrl = [struct.unpack("<iii", body[p + 12*i:p + 12*i + 12]) for i in range(n)]; p += 12*n
    dl = struct.unpack("<I", body[p:p + 4])[0]; diff = body[p + 4:p + 4 + dl]; p += 4 + dl
    el = struct.unpack("<I", body[p:p + 4])[0]; extra = body[p + 4:p + 4 + el]
    return slen, ctrl, diff, extra, d[28:44].hex()


def solve_old(lpd, target, old):
    slen, ctrl, diff, extra, _ = lpd
    op = dp = np_ = 0
    for x, y, z in ctrl:
        for k in range(x):
            o = op + k
            if 0 <= o < slen and old[o] is None:
                old[o] = (target[np_ + k] - diff[dp + k]) & 255
        np_ += x + y; op += x + z; dp += x


def apply_partial(lpd, old):
    slen, ctrl, diff, extra, _ = lpd
    out = []; op = dp = ep = 0
    for x, y, z in ctrl:
        for k in range(x):
            o = op + k; v = diff[dp + k]
            if 0 <= o < slen:
                v = None if old[o] is None else (v + old[o]) & 255
            out.append(v)
        op += x; dp += x; out += list(extra[ep:ep + y]); ep += y; op += z
    return out


# ---- dex ---------------------------------------------------------------------------

def uleb(b, p):
    r = s = 0
    while True:
        x = b[p]; p += 1
        r |= (x & 0x7f) << s; s += 7
        if x < 0x80:
            return r, p


def sleb(b, p):
    r = s = 0
    while True:
        x = b[p]; p += 1
        r |= (x & 0x7f) << s; s += 7
        if x < 0x80:
            if x & 0x40:
                r -= 1 << s
            return r, p


def enc_uleb(v):
    o = bytearray()
    while True:
        x = v & 0x7f; v >>= 7
        if v:
            o.append(x | 0x80)
        else:
            o.append(x)
            return bytes(o)


def u32(b, o):
    return struct.unpack("<I", bytes(b[o:o + 4]))[0]


def u16(b, o):
    return struct.unpack("<H", bytes(b[o:o + 2]))[0]


class Dex:
    def __init__(self, b):
        self.b = b
        (self.ns, self.os_, self.nt, self.ot, self.np_, self.op, self.nf, self.of,
         self.nm, self.om, self.nc, self.oc) = [u32(b, 0x38 + 4*i) for i in range(12)]
        self.strings = []
        for i in range(self.ns):
            n, p = uleb(b, u32(b, self.os_ + 4*i))
            e = p
            while b[e] != 0:
                e += 1
            self.strings.append(bytes(b[p:e]))
        self.types = [self.strings[u32(b, self.ot + 4*i)] for i in range(self.nt)]
        self.protos = []
        for i in range(self.np_):
            o = self.op + 12*i
            self.protos.append((self.types[u32(b, o + 4)], tuple(self.typelist(u32(b, o + 8)))))
        self.fields = [(self.types[u16(b, self.of + 8*i)], self.strings[u32(b, self.of + 8*i + 4)],
                        self.types[u16(b, self.of + 8*i + 2)]) for i in range(self.nf)]
        self.methods = [(self.types[u16(b, self.om + 8*i)], self.strings[u32(b, self.om + 8*i + 4)],
                         self.protos[u16(b, self.om + 8*i + 2)]) for i in range(self.nm)]
        self.tidx = {t: i for i, t in enumerate(self.types)}
        self.sidx = {s: i for i, s in enumerate(self.strings)}
        self.fidx = {f: i for i, f in enumerate(self.fields)}
        self.midx = {m: i for i, m in enumerate(self.methods)}
        mo = u32(b, 0x34)
        self.sections = {}
        for i in range(u32(b, mo)):
            o = mo + 4 + 12*i
            self.sections[u16(b, o)] = (u32(b, o + 4), u32(b, o + 8))

    def typelist(self, o):
        if o == 0:
            return []
        return [self.types[u16(self.b, o + 4 + 2*k)] for k in range(u32(self.b, o))]

    def classdef(self, i):
        return struct.unpack("<8I", bytes(self.b[self.oc + 32*i:self.oc + 32*i + 32]))

    def classdata(self, off):
        b = self.b; p = off; cnt = []
        for _ in range(4):
            v, p = uleb(b, p); cnt.append(v)
        out = []
        for kind in range(4):
            idx = 0; lst = []
            for _ in range(cnt[kind]):
                d, p = uleb(b, p); idx += d
                acc, p = uleb(b, p)
                if kind >= 2:
                    co, p = uleb(b, p); lst.append((idx, acc, co))
                else:
                    lst.append((idx, acc))
            out.append(lst)
        return out


def code_end(b, o):
    tries = u16(b, o + 6); insns = u32(b, o + 12)
    p = o + 16 + 2*insns
    if tries:
        if insns & 1:
            p += 2
        p += 8*tries
        n, p = uleb(b, p)
        for _ in range(n):
            sz, p = sleb(b, p)
            for _ in range(abs(sz)):
                _, p = uleb(b, p); _, p = uleb(b, p)
            if sz <= 0:
                _, p = uleb(b, p)
    return p


def type_lists(b, d, start, count):
    idx = {}; o = start
    for _ in range(count):
        o = (o + 3) & ~3
        k = u32(b, o)
        idx[tuple(d.types[u16(b, o + 4 + 2*j)] for j in range(k))] = o
        o += 4 + 2*k
    return idx


def encoded_arrays(b, start, count):
    def skip(p):
        x = b[p]; p += 1; t = x & 0x1f; a = x >> 5
        if t == 0x1c:
            n, p = uleb(b, p)
            for _ in range(n):
                p = skip(p)
            return p
        if t == 0x1d:
            _, p = uleb(b, p); n, p = uleb(b, p)
            for _ in range(n):
                _, p = uleb(b, p); p = skip(p)
            return p
        if t in (0x1e, 0x1f):
            return p
        return p + a + 1
    offs = []; o = start
    for _ in range(count):
        offs.append(o)
        n, p = uleb(b, o)
        for _ in range(n):
            p = skip(p)
        o = p
    return offs


def rebuild_tables(L, T):
    """Fill L's class_defs and class_data from T (a complete earlier version)."""
    dt, dl = Dex(T), Dex(L)
    ltl = type_lists(L, dl, dl.sections[0x1001][1], dl.sections[0x1001][0])
    eamap = dict(zip(encoded_arrays(T, dt.sections[0x2005][1], dt.sections[0x2005][0]),
                     encoded_arrays(L, dl.sections[0x2005][1], dl.sections[0x2005][0])))
    codes = []; o = dl.sections[0x2001][1]
    for _ in range(dl.sections[0x2001][0]):
        o = (o + 3) & ~3; codes.append(o); o = code_end(L, o)
    new = (NEW_METHOD[0].encode(), NEW_METHOD[1].encode(),
           (NEW_METHOD[2][0].encode(), tuple(t.encode() for t in NEW_METHOD[2][1])))
    cls = []
    for i in range(dt.nc):
        c = dt.classdef(i)
        data = [[], [], [], []]
        if c[6]:
            td = dt.classdata(c[6])
            for k in range(2):
                data[k] = [(dl.fidx[dt.fields[f]], a) for f, a in td[k]]
            for k in (2, 3):
                data[k] = [[dl.midx[dt.methods[m]], a, co] for m, a, co in td[k]]
        if dt.types[c[0]] == new[0]:
            data[2].append([dl.midx[new], NEW_METHOD_ACCESS, 1])
        for k in range(4):
            data[k].sort()
        cls.append((c, data))
    it = iter(codes)
    for c, data in sorted(cls, key=lambda x: dl.tidx[dt.types[x[0][0]]]):
        for k in (2, 3):
            for m in data[k]:
                if m[2]:
                    m[2] = next(it)
    p = dl.sections[0x2000][1]; cdoffs = []
    for c, data in cls:
        if not c[6]:
            cdoffs.append(0); continue
        cdoffs.append(p); b = bytearray()
        for k in range(4):
            b += enc_uleb(len(data[k]))
        for k in range(4):
            prev = 0
            for e in data[k]:
                b += enc_uleb(e[0] - prev) + enc_uleb(e[1]); prev = e[0]
                if k >= 2:
                    b += enc_uleb(e[2])
        L[p:p + len(b)] = list(b); p += len(b)
    tm = lambda ti: 0xffffffff if ti == 0xffffffff else dl.tidx[dt.types[ti]]
    for i, (c, data) in enumerate(cls):
        itf = 0 if c[3] == 0 else ltl[tuple(dt.typelist(c[3]))]
        src = 0xffffffff if c[4] == 0xffffffff else dl.sidx[dt.strings[c[4]]]
        sv = 0 if c[7] == 0 else eamap[c[7]]
        ent = struct.pack("<8I", tm(c[0]), c[1], tm(c[2]), itf, src, c[5], cdoffs[i], sv)
        L[dl.oc + 32*i:dl.oc + 32*i + 32] = list(ent)


def fill_anchored(L, sources, K=8):
    """Gaps outside class_defs/class_data: copy them from an earlier version when
    the K known bytes on both sides occur exactly once there, with a gap of the
    same length between them. A gap that is a string terminator gets 0."""
    oc, nc = u32(L, 0x68), u32(L, 0x60)
    mo = u32(L, 0x34); cd = None
    for i in range(u32(L, mo)):
        o = mo + 4 + 12*i
        if u16(L, o) == 0x2000:
            cd = u32(L, o + 8)
    i = 0
    while i < len(L):
        if L[i] is not None:
            i += 1; continue
        j = i
        while j < len(L) and L[j] is None:
            j += 1
        n = j - i
        if not (oc <= i < oc + 32*nc or (cd is not None and cd <= i < mo)):
            pre, post = L[i - K:i], L[j:j + K]
            if None not in pre and None not in post:
                pat_pre, pat_post = bytes(pre), bytes(post)
                for src in sources:
                    hits = []; p = src.find(pat_pre)
                    while p >= 0 and len(hits) < 2:
                        if src[p + K + n:p + K + n + K] == pat_post:
                            hits.append(p + K)
                        p = src.find(pat_pre, p + 1)
                    if len(hits) == 1:
                        L[i:j] = list(src[hits[0]:hits[0] + n]); break
                else:
                    if n == 1 and L[i - 1] is not None and L[i - 1] >= 0x20:
                        L[i] = 0  # end of a string's data
        i = j


# ---- main ------------------------------------------------------------------------

def git_show(repo, rev, path):
    return subprocess.run(["git", "-C", repo, "show", "%s:%s" % (rev, path)],
                          check=True, stdout=subprocess.PIPE).stdout


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    leafia, nemesis, out = sys.argv[1:4]
    apk = open(nemesis + "/Sources/packages/projection-tbt/files/HKMC_GPM.apk", "rb").read()
    N = zipfile.ZipFile(io.BytesIO(apk)).read("classes.dex")
    assert hashlib.md5(N).hexdigest() == NEMESIS_MD5, "NEMESIS GPM is not the expected build"
    path = "patches/ev6/HKMC_GPM.tbt.lpd"
    first = parse_lpd(git_show(leafia, "8240207", path))
    mid = parse_lpd(git_show(leafia, "c78abf6", path))
    final = parse_lpd(git_show(leafia, "08f4436", path))
    assert first[4] == NEMESIS_MD5 and mid[4] == T3_MD5 and final[4] == FINAL_MD5
    old = [None] * first[0]
    solve_old(first, N, old)
    print("stock odex bytes solved: %d of %d" % (sum(v is not None for v in old), len(old)))
    T = apply_partial(mid, old)
    assert None not in T and hashlib.md5(bytes(T)).hexdigest() == T3_MD5
    T = bytes(T)
    print("intermediate version c78abf6: complete, md5 ok")
    L = apply_partial(final, old)
    print("final: %d bytes unknown" % sum(v is None for v in L))
    fill_anchored(L, [T, N])
    print("after anchored copies: %d bytes unknown" % sum(v is None for v in L))
    rebuild_tables(L, T)
    assert None not in L, "bytes still unknown"
    b = bytes(L)
    m = hashlib.md5(b).hexdigest()
    if m != FINAL_MD5:
        raise SystemExit("result md5 %s, expected %s: not written" % (m, FINAL_MD5))
    open(out, "wb").write(b)
    print("wrote %s, md5 %s (Leafia v1.0.5 GPM code, exact)" % (out, m))


if __name__ == "__main__":
    main()
