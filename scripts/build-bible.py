#!/usr/bin/env python3
"""Build data/bible.json from Biblia Tysiaciecia V (btiv.biblia.pl).

Run once. The output is a self-contained JSON document the Quickshell panel
reads offline, so the plugin never touches the network at runtime.

    python3 scripts/build-bible.py

The site maps each book/chapter to an opaque integer id. We discover those by
asking the site's own chapter dropdown, then read each chapter page and pull the
verse markup apart. Chapter id -> book/chapter is read back from the page title
rather than trusted from the dropdown, because a few books answer the dropdown
query with an unordered list.
"""

from __future__ import annotations

import concurrent.futures
import html
import json
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

INDEX_URL = "https://btiv.biblia.pl/index.php"
CHAPTER_URL = "https://btiv.biblia.pl/rozdzial.php?id={}"
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) dad.bible-plugin/1.0"

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_PATH = ROOT / "data" / "bible.json"
CACHE_DIR = ROOT / "data" / ".cache"
WORKERS = 6
RETRIES = 3

# Book ids as offered by the site's ksiega dropdown, in canonical order.
BOOK_IDS = {
    1: "Rdz", 2: "Wj", 3: "Kpł", 4: "Lb", 5: "Pwt", 6: "Joz", 7: "Sdz",
    8: "Rt", 9: "1Sm", 10: "2Sm", 11: "1Krl", 12: "2Krl", 13: "1Krn", 14: "2Krn",
    15: "Ezd", 16: "Ne", 17: "Tb", 18: "Jdt", 19: "Est", 20: "1Mch", 21: "2Mch",
    22: "Hi", 23: "Ps", 24: "Prz", 25: "Koh", 26: "Pnp", 27: "Mdr", 28: "Syr",
    29: "Iz", 30: "Jr", 31: "Lm", 32: "Ba", 33: "Ez", 34: "Dn", 35: "Oz", 36: "Jl",
    37: "Am", 38: "Ab", 39: "Jon", 40: "Mi", 41: "Na", 42: "Ha", 43: "So", 44: "Ag",
    45: "Za", 46: "Ml", 47: "Mt", 48: "Mk", 49: "Łk", 50: "J", 51: "Dz", 52: "Rz",
    53: "1Kor", 54: "2Kor", 55: "Ga", 56: "Ef", 57: "Flp", 58: "Kol", 59: "1Tes",
    60: "2Tes", 61: "1Tm", 62: "2Tm", 63: "Tt", 64: "Flm", 65: "Hbr", 66: "Jk",
    67: "1P", 68: "2P", 69: "1J", 70: "2J", 71: "3J", 72: "Jud", 73: "Ap",
}

# Full Polish book names, used in the panel header and search results.
BOOK_NAMES = {
    "Rdz": "Księga Rodzaju", "Wj": "Księga Wyjścia", "Kpł": "Księga Kapłańska",
    "Lb": "Księga Liczbowa", "Pwt": "Księga Powtórzonego Prawa",
    "Joz": "Księga Jozuego", "Sdz": "Księga Sędziów", "Rt": "Księga Rut",
    "1Sm": "Pierwsza Księga Samuela", "2Sm": "Druga Księga Samuela",
    "1Krl": "Pierwsza Księga Królew", "2Krl": "Druga Księga Królew",
    "1Krn": "Pierwsza Księga Kronik", "2Krn": "Druga Księga Kronik",
    "Ezd": "Księga Ezdrasza", "Ne": "Księga Neemiasza", "Tb": "Księga Tobita",
    "Jdt": "Księga Judyty", "Est": "Księga Estery", "1Mch": "Pierwsza Księga Machabeusza",
    "2Mch": "Druga Księga Machabeusza", "Hi": "Księga Hioba", "Ps": "Księga Psalmów",
    "Prz": "Księga Przysłówiec", "Koh": "Księga Kohelet",
    "Pnp": "Pieśń Pieśni", "Mdr": "Księga Mądrości", "Syr": "Księga Syracha",
    "Iz": "Księga Izajasza", "Jr": "Księga Jeremiasza", "Lm": "Księga Lamentacji",
    "Ba": "Księga Barucha", "Ez": "Księga Ezechiela", "Dn": "Księga Daniela",
    "Oz": "Księga Ozeasza", "Jl": "Księga Joela", "Am": "Księga Amosa",
    "Ab": "Księga Abdiasza", "Jon": "Księga Jonasza", "Mi": "Księga Micheasza",
    "Na": "Księga Nahuma", "Ha": "Księga Habakuka", "So": "Księga Sofoniasza",
    "Ag": "Księga Aggeusza", "Za": "Księga Zachariasza", "Ml": "Księga Malachiasza",
    "Mt": "Ewangelia według św. Mateusza", "Mk": "Ewangelia według św. Marka",
    "Łk": "Ewangelia według św. Łukasza", "J": "Ewangelia według św. Jana",
    "Dz": "Dzieje Apostołów", "Rz": "List do Rzymian", "1Kor": "Pierwszy List do Koryntian",
    "2Kor": "Drugi List do Koryntian", "Ga": "List do Galatów", "Ef": "List do Efezjan",
    "Flp": "List do Filipian", "Kol": "List do Kolosian", "1Tes": "Pierwszy List do Tesaliczan",
    "2Tes": "Drugi List do Tesaliczan", "1Tm": "Pierwszy List do Tymoteusza",
    "2Tm": "Drugi List do Tymoteusza", "Tt": "List do Tytusa", "Flm": "List do Filemona",
    "Hbr": "List do Hebrajczyków", "Jk": "List Jakuba", "1P": "Pierwszy List Piotrowy",
    "2P": "Drugi List Piotrowy", "1J": "Pierwszy List Jana", "2J": "Drugi List Jana",
    "3J": "Trzeci List Jana", "Jud": "List Judy", "Ap": "Objawienie Apokalipsy",
}

# Canonical 0-based order, so the panel can sort and index without the site's ids.
BOOK_ORDER = list(BOOK_IDS.values())
BOOK_INDEX = {abbr: i for i, abbr in enumerate(BOOK_ORDER)}
NEW_TESTAMENT_INDEX = BOOK_INDEX["Mt"]

# Canonical chapter counts. The site also serves a couple of pages past the end
# of a book (an "Ap 23" stub that lists no verses); this is what they get
# checked against.
CHAPTER_COUNTS = {
    "Rdz": 50, "Wj": 40, "Kpł": 27, "Lb": 36, "Pwt": 34, "Joz": 24, "Sdz": 21,
    "Rt": 4, "1Sm": 31, "2Sm": 24, "1Krl": 22, "2Krl": 25, "1Krn": 29, "2Krn": 36,
    "Ezd": 10, "Ne": 13, "Tb": 14, "Jdt": 16, "Est": 10, "1Mch": 16, "2Mch": 15,
    "Hi": 42, "Ps": 150, "Prz": 31, "Koh": 12, "Pnp": 8, "Mdr": 19, "Syr": 51,
    "Iz": 66, "Jr": 52, "Lm": 5, "Ba": 6, "Ez": 48, "Dn": 14, "Oz": 14, "Jl": 4,
    "Am": 9, "Ab": 1, "Jon": 4, "Mi": 7, "Na": 3, "Ha": 3, "So": 3, "Ag": 2,
    "Za": 14, "Ml": 3, "Mt": 28, "Mk": 16, "Łk": 24, "J": 21, "Dz": 28, "Rz": 16,
    "1Kor": 16, "2Kor": 13, "Ga": 6, "Ef": 6, "Flp": 4, "Kol": 4, "1Tes": 5,
    "2Tes": 3, "1Tm": 6, "2Tm": 4, "Tt": 3, "Flm": 1, "Hbr": 13, "Jk": 5,
    "1P": 5, "2P": 3, "1J": 5, "2J": 1, "3J": 1, "Jud": 1, "Ap": 22,
}

TITLE_RE = re.compile(r"<title>[^<]*Testamentu\s*-\s*([^<]*)</title>")
CONTENT_RE = re.compile(r'<div class="tresc">(.*?)<div class="chapter-nav"', re.S)
FOOTNOTE_RE = re.compile(r'<sup><a[^>]*class="przypis"[^>]*>.*?</a></sup>', re.S)
HEADING_RE = re.compile(r"<div class=?(?:miedzytytul\d|tytul\d)[^>]*>.*?</div>", re.S)

# A handful of pages number a verse the site then leaves blank (Tb 9,3 and two
# others). Verse numbers come from the anchors rather than the array index, so
# those gaps survive and later verses keep their canonical numbers.
BLANK_VERSE_NOTE = "site numbers this verse but serves no text for it"
# The anchor and the printed number disagree in a few places (Kpł 4,16 is
# anchored as W1 but printed 16), so keep both and trust the printed number.
VERSE_SPLIT_RE = re.compile(
    r'<a name="W(\d+)"></a>\s*<span class="werset">\s*(\d+)(?:&nbsp;|&#160;|\s)*</span>'
)


def fetch(url: str, data: bytes | None = None) -> str:
    last: Exception | None = None
    for attempt in range(RETRIES):
        try:
            req = urllib.request.Request(
                url, data=data, headers={"User-Agent": USER_AGENT}
            )
            with urllib.request.urlopen(req, timeout=30) as response:
                return response.read().decode("utf-8", errors="replace")
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last = exc
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"failed to fetch {url}: {last}")


def chapter_ids() -> list[int]:
    """Every chapter page id the site advertises, order irrelevant.

    The chapter dropdown returns book ids -> chapter site ids, but the order
    within a book is not trustworthy (a few books answer with a bare list) and
    each book also contributes its own index page. So collect the ids only, and
    take book and chapter from each page's own title.
    """
    ids: set[int] = set()
    for book in sorted(BOOK_IDS):
        payload = urllib.parse.urlencode(
            {"action": "ksiega_change", "book": book}
        ).encode()
        parsed = json.loads(fetch(INDEX_URL, payload))
        values = parsed.values() if isinstance(parsed, dict) else parsed
        ids.update(int(v) for v in values)
    return sorted(ids)


def clean_fragment(fragment: str) -> str:
    text = re.sub(r"<br\s*/?>", " ", fragment)
    text = re.sub(r"<[^>]+>", "", text)
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def repair_numbering(numbered: list[tuple[int, str]]) -> list[dict]:
    """Put a chapter's verses back into canonical order.

    The source is a hand-maintained site, and its verse markup is wrong in a few
    dozen chapters in four ways:

    * verses out of order (Na 2 prints 3 before 2),
    * a repeated opening (Est 5 serves 1-2 twice, the second time carrying the
      Greek-text expansion),
* a verse whose anchor is missing, so the number is typed into the tail of
      the previous verse instead (Mk 9,9 sits inside the block for verse 8),
    * a genuinely skipped number, because the site merged or dropped it (Mk 9,44
      is a bracketed variant the site omits).

    Sorting and de-duplication use the printed numbers as-is: a verse numbered 4
    really is verse 4 even when a neighbour is misnumbered. A typed-in number is
    split back out only where the chapter is otherwise missing that number and the
    number follows a sentence end, so prose that merely contains a digit is never
    cut in half. What stays missing stays missing rather than being renumbered —
    main() reports the gaps.
    """
    seen: dict[int, str] = {}
    for number, text in numbered:
        seen[number] = text  # a later repeat wins, so Est 5 keeps the expansion

    for number in sorted(seen):
        following = number + 1
        if following in seen:
            continue
        text = seen[number]
        typed_in = re.search(
            rf"(?:^|(?<=[.!?:»”\"'])\s+)({following})(?=\s+[A-ZĄĆĘŁŃÓŚŹŻ])",
            text,
        )
        if typed_in:
            seen[following] = text[typed_in.end():].strip()
            seen[number] = text[: typed_in.start()].strip()

    return [{"v": number, "t": seen[number]} for number in sorted(seen)]


def parse_chapter(page: str) -> tuple[str, int | None, list[str]]:
    """Page title -> (book id, chapter number or None, verse texts).

    The title reads "Biblia Tysiaciecia ... - Jn 3"; a book's index page has no
    chapter number, which is how those pages get filtered out.
    """
    title = TITLE_RE.search(page)
    label = title.group(1).strip() if title else ""
    match = re.match(r"^(.*?)(\d+)$", re.sub(r"\s+", " ", label))
    if match:
        book = match.group(1).strip().replace(" ", "")
        chapter: int | None = int(match.group(2))
    else:
        book, chapter = label.replace(" ", ""), None

    content = CONTENT_RE.search(page)
    if not content:
        return book, chapter, []

    body = HEADING_RE.sub("", FOOTNOTE_RE.sub("", content.group(1)))
    if VERSE_SPLIT_RE.search(body):
        parts = VERSE_SPLIT_RE.split(body)
        # split() yields [lead, anchor, printed, text, anchor, printed, text, ...]
        numbered = [(int(parts[i + 1]), clean_fragment(parts[i + 2]))
                    for i in range(1, len(parts), 3)]
        return book, chapter, repair_numbering(numbered)

    # Two poetic chapters (Hi 9, Hi 28) have no per-verse anchors: the verse
    # number just starts the line, with <br> between the poetic lines. Verse
    # text then runs until the next line that starts with the next number.
    verses: list[dict] = []
    started = 0
    current: list[str] = []
    for line in re.sub(r"<br\s*/?>", "\n", body).splitlines():
        stripped = clean_fragment(line)
        if not stripped:
            continue
        leading = re.match(r"^(\d{1,3})(?:\s+|$)", stripped)
        if leading and int(leading.group(1)) == started + 1:
            if current:
                verses.append({"v": started, "t": " ".join(current)})
            started += 1
            current = [stripped[leading.end():].strip()]
        elif current:
            current.append(stripped)
    if current:
        verses.append({"v": started, "t": " ".join(current)})
    return book, chapter, verses


def format_verses(numbers: list[int]) -> str:
    """[4,5,6,9] -> '4-6,9'."""
    spans: list[tuple[int, int]] = []
    for number in numbers:
        if spans and number == spans[-1][1] + 1:
            spans[-1] = (spans[-1][0], number)
        else:
            spans.append((number, number))
    return ",".join(str(a) if a == b else f"{a}-{b}" for a, b in spans)


def load_cached(site_id: int) -> str | None:
    path = CACHE_DIR / f"{site_id}.html"
    return path.read_text(encoding="utf-8", errors="replace") if path.exists() else None


def store_cached(site_id: int, page: str) -> None:
    (CACHE_DIR / f"{site_id}.html").write_text(page, encoding="utf-8")


def collect() -> list[dict]:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    ids = chapter_ids()
    print(f"fetching {len(ids)} chapter pages", flush=True)

    pages: dict[int, str] = {}
    downloaded = 0

    def work(site: int) -> tuple[int, str]:
        cached = load_cached(site)
        if cached is not None:
            return site, cached
        return site, fetch(CHAPTER_URL.format(site))

    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for done, (site, page) in enumerate(pool.map(work, ids), start=1):
            pages[site] = page
            store_cached(site, page)
            downloaded += 1
            if done % 200 == 0 or done == len(ids):
                print(f"  {done}/{len(ids)}", flush=True)
    print(f"{len(pages)} pages ready ({downloaded} downloaded)", flush=True)

    books: dict[str, dict] = {}
    blanks: list[str] = []
    for site in ids:
        short, chapter, verses = parse_chapter(pages[site])
        if chapter is None:
            continue  # book index page
        if short not in BOOK_NAMES:
            raise RuntimeError(f"unknown book {short!r} on chapter page id={site}")
        if chapter > CHAPTER_COUNTS[short]:
            continue  # stub page past the end of the book
        if not verses:
            raise RuntimeError(f"no verses parsed for {short} {chapter} (id={site})")

        for entry in verses:
            if not entry["t"]:
                entry["t"] = BLANK_VERSE_NOTE
                blanks.append(f"{short} {chapter},{entry['v']}")

        entry = books.setdefault(
            short,
            {
                "id": short,
                "name": BOOK_NAMES[short],
                "index": BOOK_INDEX[short],
                "testament": "nt" if BOOK_INDEX[short] >= NEW_TESTAMENT_INDEX else "st",
                "chapters": [],
            },
        )
        entry["chapters"].append({"chapter": chapter, "verses": verses})

    ordered = [books[b] for b in sorted(BOOK_NAMES, key=lambda b: BOOK_INDEX[b])]
    for book in ordered:
        book["chapters"].sort(key=lambda c: c["chapter"])
    if blanks:
        print(f"  {len(blanks)} blank verse(s) marked: {', '.join(blanks)}")
    return ordered


def main() -> int:
    books = collect()

    missing = [b for b in BOOK_NAMES if b not in {book["id"] for book in books}]
    if missing:
        raise RuntimeError(f"books missing from the scrape: {', '.join(sorted(missing))}")
    for book in books:
        expected = CHAPTER_COUNTS[book["id"]]
        numbers = [c["chapter"] for c in book["chapters"]]
        if numbers != list(range(1, expected + 1)):
            gaps = sorted(set(range(1, expected + 1)) - set(numbers))
            raise RuntimeError(
                f"{book['id']}: expected chapters 1-{expected}, "
                f"got {len(numbers)}, missing {gaps}"
            )

    gaps: list[str] = []
    for book in books:
        for chapter in book["chapters"]:
            numbers = [v["v"] for v in chapter["verses"]]
            if numbers != sorted(numbers) or len(set(numbers)) != len(numbers):
                raise RuntimeError(
                    f"{book['id']} {chapter['chapter']}: verse numbers are not "
                    f"strictly increasing: {numbers}"
                )
            missing = sorted(set(range(1, numbers[-1] + 1)) - set(numbers))
            if missing:
                gaps.append(
                    f"{book['id']} {chapter['chapter']} (no {format_verses(missing)})"
                )
    if gaps:
        print(
            f"  {len(gaps)} chapter(s) have verse numbers the source skips "
            "(merged or missing verses, kept as-is):\n    " + "\n    ".join(gaps)
        )

    total_verses = sum(len(c["verses"]) for b in books for c in b["chapters"])
    document = {
        "translation": "Biblia Tysiąclecia V",
        "publisher": "Wydawnictwo Pallottinum, Poznań",
        "language": "pl",
        "books": books,
    }
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(
        json.dumps(document, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    size_mb = OUT_PATH.stat().st_size / 1024 / 1024
    print(
        f"wrote {OUT_PATH}: {len(books)} books, "
        f"{sum(len(b['chapters']) for b in books)} chapters, "
        f"{total_verses} verses, {size_mb:.1f} MB"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())