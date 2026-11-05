#!/usr/bin/env python3
"""Build the language archives behind the game's Language button.

Each language is one archive, War3zzLang_<locale>.mpq, that the engine mounts
over the game data when fs_language asks for it (FS_MountLanguagePack in
engine/common/common.c): Blizzard's own unit, spell and item names, UI strings,
font and voices for that language. The game data itself comes from a French
install, so French needs no archive.

The source is the Warcraft III 1.29.2 build on Blizzard's CDN, which still holds
every language. Only the parts of the archives that are needed are downloaded,
with range requests. Voices that a language does not localize come from the
shared War3.mpq / War3x.mpq of the local install, which is how the game resolves
them too.

The file list comes from tools/web_trace_reads.txt: everything the game reads
from the two Local archives except music, which is the same in every language.

This is Blizzard data: never commit the output or publish it to GitHub.

  python tools/lang/make_language_packs.py [--locales deDE ruRU] [--out engine/build/lang]
"""
import argparse
import hashlib
import pathlib
import re
import struct
import sys
import urllib.request
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine" / "port" / "web"))
import make_survivor_data as m  # noqa: E402

CDN = "http://eu.cdn.blizzard.com/tpr/war3"
# Build 1.29.2.9232-legacy-tft: the encoded keys of its encoding and install manifests.
ENCODING_EKEY = "8552488fa0b61c6b9f873b7393993a70"
INSTALL_EKEY = "71d74e376cedc2a3d5183494a1672b6d"
LOCALES = ("enUS", "deDE", "esES", "itIT", "plPL", "ruRU")
BASE_LOCALE = "frFR"  # What the game data already holds.
WC3 = r"C:\Program Files (x86)\Warcraft III (Legacy)"
FONT = "Fonts\\FRIZQT__.TTF"
SECTOR = 4096
# Key=value data: the engine merges every copy it finds and the last copy wins,
# so the archive's copy must hold everything, RoC keys included.
MERGED = re.compile(r"^(units\\.*\.txt|ui\\worldedit.*\.txt)$", re.I)
TEXT_EXT = (".txt", ".fdf", ".slk")

downloaded = 0


def fetch(ekey, start=None, end=None):
    global downloaded
    url = "%s/data/%s/%s/%s" % (CDN, ekey[:2], ekey[2:4], ekey)
    request = urllib.request.Request(url, headers={"User-Agent": "warcraft-survivors-language-packs"})
    if start is not None:
        request.add_header("Range", "bytes=%d-%d" % (start, end))
    with urllib.request.urlopen(request, timeout=180) as response:
        data = response.read()
    downloaded += len(data)
    return data


def unframe(chunk):
    if chunk[:1] == b"N":
        return chunk[1:]
    if chunk[:1] == b"Z":
        return zlib.decompress(chunk[1:])
    raise SystemExit("unexpected BLTE chunk mode %r" % chunk[:1])


def blte(data):
    size = struct.unpack(">I", data[4:8])[0]
    if size == 0:
        return unframe(data[8:])
    count = struct.unpack(">I", data[8:12])[0] & 0xFFFFFF
    pos, out = size, []
    for i in range(count):
        csize = struct.unpack(">I", data[12 + i * 24:16 + i * 24])[0]
        out.append(unframe(data[pos:pos + csize]))
        pos += csize
    return b"".join(out)


class Remote:
    """Random access to a BLTE file on the CDN, by decompressed offset."""

    def __init__(self, ekey):
        self.ekey = ekey
        head = fetch(ekey, 0, 7)
        if head[:4] != b"BLTE":
            raise SystemExit("not a BLTE file: " + ekey)
        header = struct.unpack(">I", head[4:8])[0]
        table = fetch(ekey, 8, header - 1)
        count = struct.unpack(">I", table[:4])[0] & 0xFFFFFF
        self.chunks, cpos, dpos = [], header, 0
        for i in range(count):
            csize, dsize = struct.unpack(">II", table[4 + i * 24:12 + i * 24])
            self.chunks.append((dpos, dsize, cpos, csize))
            cpos += csize
            dpos += dsize
        self.cache = {}

    def read(self, pos, size):
        out, end = [], pos + size
        lo, hi = 0, len(self.chunks) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if self.chunks[mid][0] <= pos:
                lo = mid
            else:
                hi = mid - 1
        i = lo
        while pos < end and i < len(self.chunks):
            dstart, dsize, cstart, csize = self.chunks[i]
            if i not in self.cache:
                self.cache[i] = unframe(fetch(self.ekey, cstart, cstart + csize - 1))
            part = self.cache[i][pos - dstart:min(end - dstart, dsize)]
            out.append(part)
            pos += len(part)
            i += 1
        return b"".join(out)


class LocalFile:
    def __init__(self, data):
        self.data = data

    def read(self, pos, size):
        return bytes(self.data[pos:pos + size])


def open_remote(ekey):
    remote = Remote(ekey)
    magic, _, _, version, shift, hpos, bpos, hcount, bcount = struct.unpack("<4sIIHHIIII", remote.read(0, 32))
    if magic != b"MPQ\x1a" or version != 0:
        raise SystemExit("not an MPQ v1 archive: " + ekey)
    hashes = struct.unpack("<%dI" % (hcount * 4),
                           m.crypt(remote.read(hpos, hcount * 16), m.mpq_hash("(hash table)", 3), False))
    blocks = struct.unpack("<%dI" % (bcount * 4),
                           m.crypt(remote.read(bpos, bcount * 16), m.mpq_hash("(block table)", 3), False))
    return {"file": remote, "sector_size": 512 << shift,
            "hashes": [list(hashes[i:i + 4]) for i in range(0, len(hashes), 4)],
            "blocks": [list(blocks[i:i + 4]) for i in range(0, len(blocks), 4)]}


def open_local(path):
    archive = m.read_archive(path)
    archive["file"] = LocalFile(archive["data"])
    return archive


def read_plain(archive, name):
    """A file's content, for files stored plain or with zlib or bzip2; None when absent."""
    found = m.find_blocks(archive, name)
    if not found:
        return None
    pos, csize, size, flags = archive["blocks"][found[0]]
    raw = archive["file"].read(pos, csize)
    key = None
    if flags & m.FILE_ENCRYPTED:
        key = m.mpq_hash(re.split(r"[\\/]", name)[-1], 3)
        if flags & m.FILE_FIX_KEY:
            key = ((key + pos) ^ size) & m.M32

    def sector(data, index, full):
        if key is not None:
            data = m.crypt(data, (key + index) & m.M32, False)
        if len(data) == full:
            return data
        if data[0] == 2:
            return zlib.decompress(data[1:])
        if data[0] == 0x10:
            import bz2
            return bz2.decompress(data[1:])
        raise SystemExit("%s: unsupported compression 0x%x" % (name, data[0]))

    if flags & m.FILE_SINGLE_UNIT:
        return sector(raw, 0, size) if flags & m.FILE_COMPRESSED else raw
    step = archive["sector_size"]
    count = (size + step - 1) // step
    if not flags & m.FILE_COMPRESSED:
        if key is None:
            return raw
        return b"".join(m.crypt(raw[i * step:(i + 1) * step], (key + i) & m.M32, False) for i in range(count))
    entries = count + 1 + (1 if flags & m.FILE_SECTOR_CRC else 0)
    table = raw[:entries * 4]
    if key is not None:
        table = m.crypt(table, (key - 1) & m.M32, False)
    offsets = struct.unpack("<%dI" % entries, table)
    return b"".join(sector(raw[offsets[i]:offsets[i + 1]], i, min(step, size - i * step)) for i in range(count))


def encoding_table():
    data = blte(fetch(ENCODING_EKEY))
    if data[:2] != b"EN":
        raise SystemExit("unexpected encoding manifest")
    ckey_size, ekey_size = data[3], data[4]
    page_size = struct.unpack(">H", data[5:7])[0] * 1024
    pages = struct.unpack(">I", data[9:13])[0]
    spec_size = struct.unpack(">I", data[18:22])[0]
    start = 22 + spec_size + pages * 32
    table = {}
    for p in range(pages):
        page = data[start + p * page_size:start + (p + 1) * page_size]
        q = 0
        while q + 6 + ckey_size <= len(page) and page[q]:
            count = page[q]
            ckey = page[q + 6:q + 6 + ckey_size].hex()
            table[ckey] = page[q + 6 + ckey_size:q + 6 + ckey_size + ekey_size].hex()
            q += 6 + ckey_size + ekey_size * count
    return table


def locale_archives():
    """{locale: {'War3Local.mpq': ekey, 'War3xLocal.mpq': ekey}} from the install manifest."""
    ekeys = encoding_table()
    raw = blte(fetch(INSTALL_EKEY))
    if raw[:2] != b"IN":
        raise SystemExit("unexpected install manifest")
    hash_size = raw[3]
    tag_count, entry_count = struct.unpack(">HI", raw[4:10])
    pos = 10
    mask_size = (entry_count + 7) // 8
    tags = {}
    for _ in range(tag_count):
        end = raw.index(b"\0", pos)
        tags[raw[pos:end].decode()] = raw[end + 3:end + 3 + mask_size]
        pos = end + 3 + mask_size
    files = []
    for _ in range(entry_count):
        end = raw.index(b"\0", pos)
        files.append((raw[pos:end].decode("latin-1"), raw[end + 1:end + 1 + hash_size].hex()))
        pos = end + 5 + hash_size
    result = {}
    for locale, mask in tags.items():
        if not re.fullmatch(r"[a-z]{2}[A-Z]{2}", locale):
            continue
        result[locale] = {name: ekeys[ckey] for i, (name, ckey) in enumerate(files)
                          if name in ("War3Local.mpq", "War3xLocal.mpq") and mask[i // 8] & (0x80 >> (i % 8))}
    return result


def traced_names(archives_base):
    """What the game reads from the Local archives, music left out (one spelling per file)."""
    wanted = m.read_list(ROOT / "tools" / "web_trace_reads.txt")
    names = {}
    for group in ("war3local.mpq", "war3xlocal.mpq"):
        for name in wanted.get(group, []):
            names.setdefault(name.lower(), name)
    # "*" entries (written in the script, numbered variants) that live in a Local archive.
    for name in wanted.get("*", []):
        if any(m.find_blocks(a, name) for a in archives_base):
            names.setdefault(name.lower(), name)
    voices = [n for k, n in sorted(names.items()) if k.endswith(".wav")]
    texts = [n for k, n in sorted(names.items()) if k.endswith(TEXT_EXT)]
    return voices, texts


def join_copies(copies):
    """Key=value files joined in archive order: later sections and keys win."""
    parts = []
    for data in copies:
        if data[:3] == b"\xef\xbb\xbf":
            data = data[3:]
        parts.append(data.rstrip(b"\x00"))
    return b"\r\n".join(parts) + b"\r\n"


def pack_sectors(data):
    """Sector table + zlib sectors, the layout WC3's own writer uses."""
    count = (len(data) + SECTOR - 1) // SECTOR
    offsets, body, used = [], [], (count + 1) * 4
    for i in range(count):
        plain = data[i * SECTOR:(i + 1) * SECTOR]
        packed = b"\x02" + zlib.compress(plain, 9)
        chunk = packed if len(packed) < len(plain) else plain
        offsets.append(used)
        body.append(chunk)
        used += len(chunk)
    offsets.append(used)
    return struct.pack("<%dI" % (count + 1), *offsets) + b"".join(body), m.FILE_EXISTS | m.FILE_COMPRESSED


class PackWriter:
    def __init__(self):
        self.files = {}  # lower name -> (name, payload, size, flags)

    def add_raw(self, archive, name):
        """Copy a file's stored bytes as they are. Returns False when the archive lacks it."""
        found = m.find_blocks(archive, name)
        if not found:
            return False
        pos, csize, size, flags = archive["blocks"][found[0]]
        if archive["sector_size"] != SECTOR:
            raise SystemExit("unexpected sector size in the source archive")
        self.files[name.lower()] = (name, archive["file"].read(pos, csize), size, flags, pos)
        return True

    def add_data(self, name, data):
        payload, flags = pack_sectors(data)
        self.files[name.lower()] = (name, payload, len(data), flags, None)

    def write(self, target):
        listing = "\r\n".join(sorted(f[0] for f in self.files.values())).encode("latin-1") + b"\r\n"
        self.add_data("(listfile)", listing)
        entries = sorted(self.files.values(), key=lambda f: f[0].lower())
        hash_count = 16
        while hash_count < len(entries) * 2:
            hash_count *= 2
        hashes = [[m.M32, m.M32, m.M32, m.M32] for _ in range(hash_count)]
        blocks, body, pos = [], [], 32
        for index, (name, payload, size, flags, old_pos) in enumerate(entries):
            if flags & m.FILE_ENCRYPTED and flags & m.FILE_FIX_KEY:
                archive = {"sector_size": SECTOR}
                payload = m.rekey(payload, name, old_pos, pos, size, flags, archive["sector_size"])
            blocks.append((pos, len(payload), size, flags))
            body.append(payload)
            pos += len(payload)
            slot = m.mpq_hash(name, 0) & (hash_count - 1)
            while hashes[slot][3] != m.M32:
                slot = (slot + 1) & (hash_count - 1)
            hashes[slot] = [m.mpq_hash(name, 1), m.mpq_hash(name, 2), 0, index]
        hash_pos = pos
        block_pos = hash_pos + hash_count * 16
        total = block_pos + len(blocks) * 16
        hash_table = m.crypt(struct.pack("<%dI" % (hash_count * 4), *(v for e in hashes for v in e)),
                             m.mpq_hash("(hash table)", 3), True)
        block_table = m.crypt(struct.pack("<%dI" % (len(blocks) * 4), *(v for e in blocks for v in e)),
                              m.mpq_hash("(block table)", 3), True)
        header = struct.pack("<4sIIHHIIII", b"MPQ\x1a", 32, total, 0, 3, hash_pos, block_pos, hash_count, len(blocks))
        target.parent.mkdir(parents=True, exist_ok=True)
        temp = target.with_name(target.name + ".tmp")
        with open(temp, "wb") as out:
            out.write(header)
            for payload in body:
                out.write(payload)
            out.write(hash_table)
            out.write(block_table)
        temp.replace(target)
        return total


def build(locale, ekeys, shared, voices, texts, base_font_size, out):
    print(locale, flush=True)
    local = open_remote(ekeys["War3Local.mpq"])
    xlocal = open_remote(ekeys["War3xLocal.mpq"])
    # The order the engine searches: War3 < War3Local < War3x < War3xLocal.
    order = [shared["War3.mpq"], local, shared["War3x.mpq"], xlocal]
    pack = PackWriter()
    missing = []
    for name in voices:
        if not any(pack.add_raw(archive, name) for archive in reversed(order)):
            missing.append(name)
    voice_count = len(pack.files)
    for name in texts:
        if MERGED.match(name):
            copies = [read_plain(archive, name) for archive in order]
            copies = [c for c in copies if c]
            if copies:
                pack.add_data(name, join_copies(copies))
            else:
                missing.append(name)
        elif not any(pack.add_raw(archive, name) for archive in reversed(order)):
            missing.append(name)
    # The font only when it differs from the base one (Polish and Russian need more glyphs).
    for archive in (xlocal, local):
        found = m.find_blocks(archive, FONT)
        if found:
            if archive["blocks"][found[0]][2] != base_font_size:
                pack.add_raw(archive, FONT)
            break
    target = out / ("War3zzLang_%s.mpq" % locale)
    size = pack.write(target)
    sha1 = hashlib.sha1(target.read_bytes()).hexdigest()
    print("  %s: %.1f MB, %d voices, %d text files, sha1 %s, downloaded so far %.0f MB" %
          (target.name, size / 1048576, voice_count, len(pack.files) - voice_count - 1, sha1[:10], downloaded / 1048576))
    if missing:
        print("  not in this language (the base copy stays): %d, first: %s" % (len(missing), missing[:4]))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--locales", nargs="*", default=list(LOCALES))
    parser.add_argument("--wc3", default=WC3, help="Warcraft III 1.29 folder (the shared War3.mpq, War3x.mpq)")
    parser.add_argument("--out", default=str(ROOT / "engine" / "build" / "lang"))
    args = parser.parse_args()
    wc3 = pathlib.Path(args.wc3)
    shared = {name: open_local(wc3 / name) for name in ("War3.mpq", "War3x.mpq")}
    base = [open_local(wc3 / name) for name in ("War3Local.mpq", "War3xLocal.mpq")]
    voices, texts = traced_names(base)
    print("%d voices, %d text files traced" % (len(voices), len(texts)))
    base_font = next(a["blocks"][m.find_blocks(a, FONT)[0]][2] for a in reversed(base) if m.find_blocks(a, FONT))
    archives = locale_archives()
    for locale in args.locales:
        if locale == BASE_LOCALE:
            continue
        if locale not in archives:
            raise SystemExit("this build has no " + locale)
        build(locale, archives[locale], shared, voices, texts, base_font, pathlib.Path(args.out))


if __name__ == "__main__":
    main()
