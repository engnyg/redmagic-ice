#!/usr/bin/env python3
"""把韌體檔注入 IPA 的 App 包(個人版,不要公開散佈)。

用法:
    python3 tools/inject_firmware.py <輸入.ipa> <韌體資料夾> <輸出.ipa>

- 只注入「SHA-256 在已知清單內」且通過 Telink 映像檔驗證的 .bin;其他檔案會被略過並提示。
- 檔案以 <sha256>.bin 命名放進 Payload/RedMagicIce.app/Firmware/,App 啟動時會自動登錄為「內建」。
- 韌體是努比亞與冰環作者的檔案:產出的 IPA 請只自己使用,不要上傳到公開倉庫或 Release。
"""
import hashlib, os, struct, sys, zipfile, zlib

KNOWN = {  # 與 RedMagicIce/Protocol/FirmwareCatalog.swift 保持一致
    "7f7219630f7ca86d4d72abc5fd99e530655eae86bf05ca5e4407f25fd36b3148": "SRQ_8PRO V8.4.7 (官方)",
    "b6ae7340b2b1ff4e896252070af22c0492313eb41770c71344cfbe6da86f6f6f": "SRQ_8PRO V8.5.2 R2 (新燈效)",
    "3db37337196a70fbde1fa94bc376aa8c689184ee293535e247ea85c049bcff74": "SRQ_8PRO V8.5.3 R2 (超頻)",
    "2ef552d1ea9b5fa2a453ec79bcb3f8b7500a080b2a0a5ef5762ef04de4926542": "8.4.9 MaxFan (超頻)",
    "4d8f37960e9984f4e6b2fddce88f7dafc70b1964760d3677e899f8401dc74423": "8Pro V8.2.5 (超頻)",
    "1370c3f5dde5767593ff30a62dbac6d791ff193f93009e5a9dcd7b785b640df9": "8Pro 超頻 V8.4.3",
}

def valid_telink(d: bytes) -> bool:
    n = len(d)
    if not (1024 <= n < 126976 and n % 16 == 4): return False
    if d[8:12] != b"KNLT": return False
    if struct.unpack_from("<I", d, 24)[0] != n: return False
    return struct.unpack_from("<I", d, n - 4)[0] == (zlib.crc32(d[:n - 4]) ^ 0xFFFFFFFF) & 0xFFFFFFFF

def main(src, fw_dir, dst):
    found = {}
    for root, _, files in os.walk(fw_dir):
        for f in files:
            if not f.lower().endswith(".bin"): continue
            d = open(os.path.join(root, f), "rb").read()
            sha = hashlib.sha256(d).hexdigest()
            if sha not in KNOWN: print(f"略過(不在已知清單):{f}"); continue
            if not valid_telink(d): print(f"略過(驗證失敗):{f}"); continue
            found[sha] = d
    if not found: sys.exit("沒有可注入的韌體")
    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, "w") as zout:
        app = next(i.filename.split("/")[1] for i in zin.infolist() if i.filename.startswith("Payload/") and i.filename.count("/") >= 2)
        for item in zin.infolist():                       # 保留原本的權限位元(可執行檔)與壓縮方式
            zout.writestr(item, zin.read(item.filename))
        for sha, d in found.items():
            zi = zipfile.ZipInfo(f"Payload/{app}/Firmware/{sha}.bin"); zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = 0o644 << 16
            zout.writestr(zi, d)
            print(f"已注入:{KNOWN[sha]}  {sha[:12]}")
    print(f"完成:{dst}({os.path.getsize(dst)} 位元組)")

if __name__ == "__main__":
    if len(sys.argv) != 4: sys.exit(__doc__)
    main(*sys.argv[1:])
