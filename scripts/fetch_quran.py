"""Downloads the Quran (Arabic Uthmani + Urdu translation) into a bundled asset.

The text is NEVER authored or paraphrased here — it is fetched verbatim from
quran.com's public API and checked for structural integrity before it is
written. Scripture that is subtly wrong is worse than no feature at all, so the
script refuses to emit a file unless every surah has exactly the ayah count the
Quran actually has.

Usage:
  python scripts/fetch_quran.py            # writes assets/quran/quran_ur.json
  python scripts/fetch_quran.py --check    # verifies the existing asset only

Translation is Maulana Muhammad Junagarhi (quran.com edition 54), the plain
Urdu rendering used in the Saudi-printed Urdu mushaf and the one most widely
read in Pakistan.
"""

import argparse
import json
import os
import sys
import time
import urllib.request

API = "https://api.quran.com/api/v4"
TRANSLATION_ID = 54  # Maulana Muhammad Junagarhi — Urdu
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "quran", "quran_ur.json")

# Ayah count of every surah, in order. This is the integrity check: the API
# could change, a request could truncate, a translation could be missing
# verses. None of that may reach users silently.
AYAH_COUNTS = [
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128,
    111, 110, 98, 135, 112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73,
    54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38, 29, 18, 45, 60,
    49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12, 12, 30, 52, 52,
    44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25, 22, 17, 19,
    26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9, 5, 4, 7, 3,
    6, 3, 5, 4, 5, 6,
]
TOTAL_AYAHS = 6236


def get(url, tries=8):
    last = None
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "pakbazar-quran-fetch"})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as exc:  # network here is unreliable; retry patiently
            last = exc
            time.sleep(3 + attempt * 2)
    raise SystemExit(f"giving up on {url}: {last!r}")


def fetch_chapter_names():
    data = get(f"{API}/chapters?language=en")
    out = {}
    for c in data["chapters"]:
        out[c["id"]] = {
            "name_arabic": c["name_arabic"],
            "name_simple": c["name_simple"],
            "translated": c["translated_name"]["name"],
            "revelation": c["revelation_place"],
            "ayahs": c["verses_count"],
        }
    return out


def fetch_chapter(num):
    verses, page = [], 1
    while True:
        d = get(
            f"{API}/verses/by_chapter/{num}?fields=text_uthmani"
            f"&translations={TRANSLATION_ID}&per_page=50&page={page}"
        )
        for v in d["verses"]:
            tr = v.get("translations") or []
            verses.append(
                {
                    "n": int(v["verse_key"].split(":")[1]),
                    "ar": v["text_uthmani"],
                    "ur": tr[0]["text"] if tr else "",
                }
            )
        meta = d.get("pagination") or {}
        if not meta.get("next_page"):
            break
        page = meta["next_page"]
    return verses


def verify(payload):
    """Refuses anything structurally wrong. Loud, not silent."""
    problems = []
    surahs = payload["surahs"]
    if len(surahs) != 114:
        problems.append(f"expected 114 surahs, got {len(surahs)}")
    total = 0
    for i, s in enumerate(surahs):
        expected = AYAH_COUNTS[i]
        got = len(s["verses"])
        total += got
        if got != expected:
            problems.append(f"surah {i + 1}: expected {expected} ayahs, got {got}")
        for v in s["verses"]:
            if not v["ar"].strip():
                problems.append(f"surah {i + 1}:{v['n']} has empty Arabic")
            if not v["ur"].strip():
                problems.append(f"surah {i + 1}:{v['n']} has empty Urdu")
    if total != TOTAL_AYAHS:
        problems.append(f"expected {TOTAL_AYAHS} ayahs in total, got {total}")
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="verify the existing asset")
    args = ap.parse_args()

    if args.check:
        if not os.path.exists(OUT):
            raise SystemExit(f"missing {OUT}")
        payload = json.load(open(OUT, encoding="utf-8"))
    else:
        names = fetch_chapter_names()
        surahs = []
        for n in range(1, 115):
            verses = fetch_chapter(n)
            meta = names[n]
            surahs.append(
                {
                    "n": n,
                    "ar": meta["name_arabic"],
                    "en": meta["name_simple"],
                    "meaning": meta["translated"],
                    "place": meta["revelation"],
                    "verses": verses,
                }
            )
            print(f"  {n:3d}/114  {meta['name_simple']:<20} {len(verses):>3} ayahs", flush=True)
        payload = {
            "source": "https://api.quran.com/api/v4",
            "arabic": "Uthmani",
            "translation": "Maulana Muhammad Junagarhi (Urdu)",
            "translation_id": TRANSLATION_ID,
            "surahs": surahs,
        }

    problems = verify(payload)
    if problems:
        print("\nINTEGRITY CHECK FAILED — refusing to write:", file=sys.stderr)
        for p in problems[:25]:
            print("  -", p, file=sys.stderr)
        raise SystemExit(1)

    if not args.check:
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        with open(OUT, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(OUT)
    print(f"\nOK — 114 surahs, {TOTAL_AYAHS} ayahs, {size / 1024 / 1024:.2f} MB")


if __name__ == "__main__":
    main()
