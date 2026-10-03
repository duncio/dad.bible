# Biblia Tysiąclecia — an Omarchy bar plugin

Read **Biblia Tysiąclecia V**, the standard Catholic Bible in Polish, from the
bar. The whole text is bundled as JSON, so the panel opens instantly, search
works offline, and nothing is fetched at runtime.

| | |
| --- | --- |
| Text | Biblia Tysiąclecia V (wydanie V), Wydawnictwo Pallottinum |
| Coverage | 73 books · 1,328 chapters · 35,384 verses · 4.9 MB |
| Network | none at runtime; only `scripts/build-bible.py` uses the network |
| Entry point | `~/.config/omarchy/plugins/dad.bible/` |

---

## Contents

- [Using it](#using-it)
- [How it works](#how-it-works)
- [Reference syntax](#reference-syntax)
- [Search](#search)
- [The verse of the day](#the-verse-of-the-day)
- [Bookmarks](#bookmarks)
- [Settings](#settings)
- [Rebuilding the text](#rebuilding-the-text)
- [Tests](#tests)
- [Development notes](#development-notes)
- [Troubleshooting](#troubleshooting)

---

## Using it

The bar shows the day's verse as a reference (`Mk 10,27`). Click it to open the
panel; the panel is one search field above one list.

### Typing

| Input | Effect |
| --- | --- |
| `J 3,16` | jumps straight to that verse |
| `1 Kor 13,4-7` | jumps to the start of the range |
| `ps 23` | jumps to the chapter |
| `obj 22` | full name works too |
| `miłość` | searches all 35,384 verses |
| `milosc` | same — diacritics are optional |
| `@` | lists your bookmarks |
| `@j 3` | filters bookmarks by reference |

### Keys

| Key | Action |
| --- | --- |
| `↑` `↓` | previous / next verse; move through results when searching |
| `Enter` | open the highlighted result, or the next verse when nothing is typed |
| `Esc` | clear the query; closes the panel if already empty |
| `Ctrl+N` / `Ctrl+P` | next / previous chapter, staying on the same verse |
| `Ctrl+D` | jump to the verse of the day |
| `Ctrl+B` | bookmark or unbookmark the current verse |
| `Tab` | move to the next bar panel |

Space is deliberately **not** bound: Polish references contain one. Plain letters
always reach the search field.

---

## How it works

```
Bar ──► Panel.qml ──► Service.qml ──► data/bible.json
             │             │
             │             └── search, bookmarks, verse stepping
             └── parse "J 3,16", decide what Enter means
                         Model.js (no QML at all)
```

### Files

| File | Role |
| --- | --- |
| `manifest.json` | Registers the plugin with the shell; declares the settings schema |
| `Panel.qml` | The bar button and the panel. All layout, keys, and navigation state |
| `Service.qml` | Owns the parsed text, the verse index, search, and the bookmark store |
| `Model.js` | Pure JS: Polish folding, reference parsing, search scoring, the daily rotation |
| `data/bible.json` | The generated text |
| `scripts/build-bible.py` | The generator — run once by hand, never at runtime |
| `tests/run` | Runs all three suites |

### Why the split

`Model.js` has **no QML dependency**. That is deliberate: everything hardest to
get right — parsing what people type, folding diacritics, ranking results — is
plain JavaScript, so it can be tested under `node` in a second instead of
through a live panel.

`Service.qml` is the only part that touches the disk or spawns a process, and
`Panel.qml` is the only part that draws anything. Neither holds logic the other
two need.

### At startup

`Service.qml` reads `data/bible.json` once and flattens it into a list of verses,
each with a **folded** copy of its text (lowercased, diacritics stripped). That
copy is what search scans, so a keystroke never re-runs the regexes over the
whole Bible. Loading takes well under a second and happens while the panel is
still closed.

---

## Reference syntax

Parsing is deliberately forgiving, because people type references in whatever
shape is habitual.

**Accepted forms**

| You type | It resolves to |
| --- | --- |
| `J 3,16` `j 3,16` `J3,16` | `J 3,16` |
| `J 3.16` `J 3:16` | `J 3,16` — the Polish comma, a dot, or a colon |
| `1 Kor 13,4-7` | `1Kor 13,4` (start of the range) |
| `1Kor 13,7-4` | `1Kor 13,4` — a reversed range is normalised |
| `ps 23` `psalm 23,1` | `Ps 23,1` |
| `koryntian 13,4` | `1Kor 13,4` |
| `lukasza 2,14` `Łk 2,14` | `Łk 2,14` |
| `j` | the book alone, landing on chapter 1 verse 1 |
| `miłość` | **not** a reference — falls through to search |
| `a tak dalej` | **not** a reference — falls through to search |

**Rules that matter**

- Book ids are canonical short forms (`Rdz`, `1Kor`, `Łk`, `Ap`), listed in
  `Model.js` alongside their full Polish names and aliases.
- Aliases are matched **longest-first**, so `1 kor` beats `kor` and a bare `j`
  never shadows `1j`.
- Book names are in the **genitive**: `Ewangelia według św. Łukasza`, not
  `Łuki`. This is Polish grammar for "according to"; the nominative reads wrong.
- Numbers are looked up **by number, not array position**. The source skips some
  verse numbers (see [Rebuilding the text](#rebuilding-the-text)), so position and
  number are not the same thing, and a jump must use the number.

---

## Search

Search runs over the folded text, so `milosc`, `Miłość`, and `miłość` all find
the same verses.

**Matching.** Every term must appear in a verse (AND). A whole-word hit scores
higher than one buried inside another word.

**Ranking.** By score, then by verse length, then by canonical order:

1. Whole-word hits first — a mid-word match still matches, but ranks lower.
2. Shorter verses next — among equally relevant verses, the compact one is the
   more direct answer. This is what stops a two-word fragment like
   *„Niech trwa braterska miłość."* from outranking a verse that says something.
3. Canonical order as a tie-break, so results never reshuffle between identical
   searches.

**Notes on what search will not do.** It does not stem: `umiłował` will not find
*„umiłowali"*, and `miłość` will not find `J 3,16` (which reads `umiłował`). It
is substring matching over folded text, nothing more clever.

---

## The verse of the day

The bar label and the initial reading position come from a hand-curated list of
60 verses in `Model.js` (`DAILY`). Day-of-year picks the entry, so:

- the same day always shows the same verse, across restarts;
- the rotation never repeats within a single pass;
- no state is stored.

`Ctrl+D` jumps to it at any time.

**The label updates at midnight on a running shell.** The binding reads
`today`, which is backed by a `SystemClock` at hour precision — it emits
`dateChanged` on each hour boundary, so midnight rolls the label over. This
matters because the obvious version of this code is subtly wrong:

```qml
readonly property var current: service.loaded ? service.dailyReference(new Date()) : null
```

That looks correct and passes every casual test, but `new Date()` is not a
dependency, so the binding evaluates **once** and never again. The label then
shows the day the plugin *loaded*, not today — correct at load, stale forever
after. On a shell that stays up for weeks, the rotation silently stops.

The panel suite catches this by standing the panel on tomorrow and asserting the
label follows; a value check cannot, because at load time the frozen and correct
answers agree.

The list is also checked: one test walks **every day of the year** and asserts
each reference resolves to a real verse in the bundled text. That check earned
its keep — it caught two bad entries (`Lk` instead of `Łk`, and Joel's
outpouring of the Spirit, which this source numbers `Jl 3,1` rather than
`Jl 2,28`).

---

## Bookmarks

`Ctrl+B` bookmarks the current verse. Stored as plain reference strings, newest
first:

```json
["J 3,16", "Ps 23,1"]
```

Location: `Quickshell.statePath("omarchy/dad.bible/bookmarks.json")`, which
resolves under `~/.local/state/quickshell/by-shell/<id>/`. Editable by hand — only
well-formed references are loaded back, so a typo is skipped rather than
breaking the panel.

Writes go through `printf` with the JSON as a positional parameter, so quotes and
diacritics survive. A burst of toggles cannot outrun the writer: the last payload
is remembered and flushed when the running write finishes.

---

## Settings

Configured in `~/.config/omarchy/shell.json`, editable from Omarchy Settings.

| Setting | Default | Effect |
| --- | --- | --- |
| `showVerseInTooltip` | `true` | Hover the bar label to see the full verse of the day instead of just its reference |

The plugin currently exposes one setting. Adding another means: a property on
`Panel.qml`, an entry in `manifest.json`'s `barWidget.schema`, and a check in
`tests/test-panel.qml` if it changes behaviour.

---

## Rebuilding the text

`data/bible.json` is generated from **btiv.biblia.pl** (Wydawnictwo Pallottinum).
Only re-run this when changing *how* the source is read — book names, the
reference syntax, or the panel never need it.

```
cd ~/.config/omarchy/plugins/dad.bible
python3 scripts/build-bible.py
```

It caches every page under `data/.cache`, so a second run needs no network.
Roughly 1,333 pages, a few minutes.

**Before writing, the script verifies:** all 73 books present, chapter numbers
contiguous in every book, verse numbers strictly increasing within every
chapter, and no verse left empty. A failure aborts without touching the existing
`data/bible.json`.

### What the source gets wrong

The site is maintained by hand, and its verse markup is wrong in about 40
chapters. The script repairs what it can and **reports** the rest rather than
quietly renumbering:

| Defect | Example | What happens |
| --- | --- | --- |
| Verses out of order | `Na 2` prints verse 3 before verse 2 | Sorted by printed number |
| Repeated opening | `Est 5` serves 1-2 twice, the second with the Greek-text expansion | The later copy wins |
| Missing anchor | `Mk 9,9` has no anchor; its number is typed into the tail of verse 8 | Split back out — but only where the chapter genuinely misses that number *and* the number follows a sentence end |
| Number skipped | `Mk 9,44`, a verse the translation brackets as a variant | Left missing. Verse numbers are never shifted, because one shifted verse silently misquotes every verse after it |
| Numbered but blank | `Tb 9,3`, `Tb 11,2`, `Tb 14,8` | Carries a note in place of the text |

The current state of the last two, as built: **37 chapters skip 64 verses**, and
**3 verses are blank**. Both lists are printed on every build.

The repair is deliberately conservative. Renumbering a chapter to "look right"
is the one change that would be invisible in testing and wrong in use, so the
script refuses to do it. A skipped verse means the text is genuinely absent; a
lookup for it correctly returns nothing rather than returning the wrong verse.

---

## Tests

```
tests/run            all three suites
tests/run model      Model.js against data/bible.json, under node
tests/run service    Service.qml under qs: loading, lookup, stepping, bookmarks
tests/run panel      Panel.qml under qs: shortcuts and navigation
```

149 checks, a few seconds.

| Suite | Covers |
| --- | --- |
| **model** | Diacritics folding; every reference form in the table above; things that must *not* parse as a reference; verse-by-number lookup; search ranking, limits, and no-match cases; genitive book names; model/data agreement across all 73 books; every day of the year resolving |
| **service** | Loading and error paths; verse lookup including the skipped-number gaps; chapter stepping across book boundaries in both directions; the daily verse; bookmark add/remove/filter/persistence shape |
| **panel** | Navigation and shortcuts, by driving `handleKey()` with synthetic key events — including that Space and plain letters are left alone for the field, and that `Ctrl+C` and friends reach the field untouched. Also stands the panel on a different day to prove the verse-of-the-day label follows the clock rather than freezing at load |

**The panel suite needs no compositor.** `handleKey()` takes a plain object with
`key`, `modifiers`, and `accepted`, so the whole keyboard state machine is
testable directly.

**Test isolation.** The qs suites read the plugin from `BIBLE_PLUGIN_DIR`
(default `~/.config/omarchy/plugins/dad.bible`) and point bookmarks at a scratch
file, so a test run never touches the real store. `tests/run panel` also links
the shell's `Commons` and `Ui` into a scratch directory, because quickshell
resolves `qs.Commons` relative to the config file.

**Two environment quirks worth knowing.** A standalone `qs` run blackholes every
URL, including the config file's own, so relative `Qt.resolvedUrl()` does not
work there — hence `BIBLE_PLUGIN_DIR`. And `wtype` on this machine sends
modifiers as `0`, so `Ctrl+B` cannot be verified by synthesised key presses; the
panel suite covers that path instead.

---

## Development notes

**Editing the plugin reloads automatically.** Saving any file under
`~/.config/omarchy/plugins/` reloads the plugin in the running shell. If a change
somehow does not apply:

```
omarchy-shell shell rescanPlugins
```

**Bar layout.** The widget is in the `right` section of `shell.json`. Move it
with:

```
omarchy bar move dad.bible --section left
```

**Panel height is fixed, not measured.** The reading area is a `ListView`, whose
implicit height is zero until its delegates exist, so a content-measured card
collapses on open. The height is a constant for that reason.

**The bar button is a `WidgetButton`, not a `BarIconButton`.** `BarIconButton`
pins itself to a 27px icon canvas and lets the glyph paint outside it — fine for
an icon, wrong for a text label as wide as `Mk 10,27`, which then draws over its
neighbours. A `WidgetButton` sizes to its text. The clock widget solves the same
shape problem the same way, including `openPanelIndicatorWidth`.

**Keep `Model.js` QML-free.** Anything that can live there should, so it stays
testable under `node`.

**Reference one-way binding.** The search field owns its own text and reports
changes upward. Binding both ways makes the two fight and silently drops
keystrokes.

**Never bind to `new Date()`.** Any binding that wants "now" needs something
observable to depend on, or it evaluates once and never again. Use the panel's
`today` (clock-backed), never a bare `new Date()`. This is the single easiest
mistake in this file to make and the hardest to notice.

---

## Troubleshooting

**Panel opens empty or shows nothing.** Check the text is present:

```
ls -l ~/.config/omarchy/plugins/dad.bible/data/bible.json
```

If missing, run `python3 scripts/build-bible.py`. The panel header shows the
load error in place of the subtitle if parsing fails.

**A verse search finds nothing where text exists.** Check the folding: `J 3,16`
contains `umiłował`, not `miłość`. Search does not stem.

**A jump reports "nie ma takiego rozdziału".** The reference parsed but that
chapter does not exist. Some chapters are shorter than you would expect — Joel 2
has 27 verses here, not 32.

**Changing `showVerseInTooltip` has no effect.** Settings are read from the
widget's own `shell.json` entry. Confirm the entry is under the widget id
`dad.bible`, then `omarchy-shell shell rescanPlugins`.

**The label overlaps its neighbours again.** Do not swap the bar button for
`BarIconButton`. See [Development notes](#development-notes).

---

## Text

Biblia Tysiąclecia V © Wydawnictwo Pallottinum, Poznań. Bundled here for personal
reading; not for redistribution.
