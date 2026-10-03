// Exercises Model.js against the bundled bible.json, so reference parsing and
// search are verified without opening the panel.
//
//   node tests/test-model.js
//
// Rebuilds the flat verse list the same way Service.qml does, then checks that
// every canonical reference resolves, that Polish diacritics fold to the same
// key, and that search finds the verses it should.

const fs = require("fs");
const path = require("path");
const Model = require("../Model.js");

const DATA = path.join(__dirname, "..", "data", "bible.json");

let failures = 0;
function check(name, condition, detail) {
  if (condition) {
    console.log("  ok   " + name);
  } else {
    failures += 1;
    console.log("  FAIL " + name + (detail ? " — " + detail : ""));
  }
}

// bible.json stores each verse as { v, t } so verse numbers survive the gaps the
// source has. Service.qml flattens it the same way.
function flatVerses(doc) {
  const verses = [];
  for (const book of doc.books) {
    for (const chapter of book.chapters) {
      for (const entry of chapter.verses) {
        verses.push({
          book: book.id,
          chapter: chapter.chapter,
          verse: entry.v,
          text: entry.t,
          folded: Model.fold(entry.t)
        });
      }
    }
  }
  return verses;
}

console.log("bible.json");
if (!fs.existsSync(DATA)) {
  console.log("  FAIL missing data/bible.json — run scripts/build-bible.py");
  process.exit(1);
}
const doc = JSON.parse(fs.readFileSync(DATA, "utf8"));
check("73 books", doc.books.length === 73, String(doc.books.length));
check("translation recorded", doc.translation === "Biblia Tysiąclecia V", doc.translation);

const byId = Object.create(null);
for (const book of doc.books) byId[book.id] = book;
check("every book id known to the model",
  doc.books.every((book) => Model.BOOK_NAMES[book.id] !== undefined));
check("book chapters are contiguous",
  doc.books.every((book) => book.chapters.every((chapter, index) => chapter.chapter === index + 1)));
check("no empty verse text",
  doc.books.every((book) => book.chapters.every((chapter) => chapter.verses.every((v) => v.t.trim().length > 0))));
check("verse numbers strictly increase within a chapter",
  doc.books.every((book) => book.chapters.every((chapter) => {
    const numbers = chapter.verses.map((v) => v.v);
    return numbers.every((n, i) => i === 0 || n > numbers[i - 1]);
  })));
// One chapter genuinely has no verse 1: the site never wrote one for Syr 6.
const missingFirst = [];
for (const book of doc.books) {
  for (const chapter of book.chapters) {
    if (chapter.verses[0].v !== 1) missingFirst.push(book.id + " " + chapter.chapter);
  }
}
check("only Syr 6 lacks a verse 1", missingFirst.join(",") === "Syr 6", missingFirst.join(","));
check("Syr 6 starts at verse 2", byId.Syr.chapters[5].verses[0].v === 2);
check("deuterocanonical books present", ["Ba", "Mdr", "Syr", "1Mch", "2Mch", "Jud"].every((id) => byId[id]));

// Gospel names are in the genitive ("według św. Łukasza"), not the nominative.
check("gospel names are genitive",
  byId.Mt.name === "Ewangelia według św. Mateusza"
  && byId.Mk.name === "Ewangelia według św. Marka"
  && byId.Łk.name === "Ewangelia według św. Łukasza"
  && byId.J.name === "Ewangelia według św. Jana",
  [byId.Mt.name, byId.Mk.name, byId.Łk.name, byId.J.name].join(" / "));
check("the model and the data agree on book names",
  doc.books.every((book) => Model.bookName(book.id) === book.name),
  doc.books.filter((book) => Model.bookName(book.id) !== book.name)
    .map((book) => book.id + ": " + book.name + " vs " + Model.bookName(book.id)).join("; "));
check("an alias resolves to the same name",
  ["lukasza 2,14", "luka 2,14", "koryntian 13,4"].every((input) => {
    const parsed = Model.parseReference(input);
    return parsed && Model.bookName(parsed.book) === byId[parsed.book].name;
  }));

const verses = flatVerses(doc);
console.log("verses: " + verses.length);

console.log("folding");
check("milosc == milość", Model.fold("miłość") === Model.fold("milosc"), Model.fold("miłość"));
check("diacritics stripped", Model.fold("Łk 3,16 Wciąż") === "lk 3,16 wciaz", Model.fold("Łk 3,16 Wciąż"));
check("hyphens become spaces", Model.fold("Mój-Bóg") === "moj bog", Model.fold("Mój-Bóg"));
check("quotes become spaces", Model.fold("«czyn»") === "czyn", Model.fold("«czyn»"));

console.log("reference parsing");
const cases = [
  ["J 3,16", "J", 3, 16],
  ["j 3,16", "J", 3, 16],
  ["J3,16", "J", 3, 16],
  ["J 3.16", "J", 3, 16],
  ["J 3:16", "J", 3, 16],
  ["1 Kor 13,4", "1Kor", 13, 4],
  ["1kor 13,4", "1Kor", 13, 4],
  ["koryntian 13,4", "1Kor", 13, 4],
  ["Ps 23", "Ps", 23, 0],
  ["psalm 23,1", "Ps", 23, 1],
  ["1 J 5,14", "1J", 5, 14],
  ["1j 5,14", "1J", 5, 14],
  ["2 P 3,16", "2P", 3, 16],
  ["Obj 3,20", "Ap", 3, 20],
  ["Rdz 1,1", "Rdz", 1, 1],
  ["Ba 6,17", "Ba", 6, 17],
  ["Łk 2,14", "Łk", 2, 14]
];
for (const [input, book, chapter, verse] of cases) {
  const parsed = Model.parseReference(input);
  const ok = parsed && parsed.book === book && parsed.chapter === chapter && parsed.verse === verse;
  check(input + " -> " + book + " " + chapter + (verse ? "," + verse : ""),
    ok, parsed ? JSON.stringify(parsed) : "null");
}
check("range parsed", (() => {
  const r = Model.parseReference("1 Kor 13,4-7");
  return r && r.book === "1Kor" && r.chapter === 13 && r.verse === 4 && r.end === 7;
})());
check("reversed range normalised", (() => {
  const r = Model.parseReference("1 Kor 13,7-4");
  return r && r.verse === 4 && r.end === 7;
})());
check("book alone", (() => {
  const r = Model.parseReference("j");
  return r && r.book === "J" && r.chapter === 0;
})());
check("search text is not a reference", Model.parseReference("miłość") === null);
check("random words are not a reference", Model.parseReference("a tak dalej") === null);
check("empty is not a reference", Model.parseReference("") === null);

console.log("reference resolution against the text");
// Verse numbers are looked up by number, not array position: the source skips
// numbers in a few dozen chapters and the panel addresses verses the same way.
function resolve(input) {
  const parsed = Model.parseReference(input);
  if (!parsed) return null;
  const book = byId[parsed.book];
  if (!book || !parsed.chapter) return book ? { book: book.id } : null;
  const chapter = book.chapters[parsed.chapter - 1];
  if (!chapter) return null;
  const texts = chapter.verses.map((v) => v.t);
  return { book: book.id, chapter: chapter.chapter, texts: texts, verse: parsed.verse };
}
function verseText(resolved) {
  if (!resolved) return null;
  return resolved.texts[resolved.verse - 1] || null;
}
const john316 = resolve("J 3,16");
check("J 3,16 text", verseText(john316) && verseText(john316).indexOf("Jednorodzonego") >= 0,
  verseText(john316) || "unresolved");
const cor134 = resolve("1 Kor 13,4");
check("1 Kor 13,4 text", verseText(cor134) && verseText(cor134).indexOf("Miłość cierpliwa") >= 0,
  verseText(cor134) || "unresolved");
const ps231 = resolve("Ps 23,1");
check("Ps 23,1 text", verseText(ps231) && verseText(ps231).indexOf("moim pasterzem") >= 0,
  verseText(ps231) || "unresolved");
const gen11 = resolve("Rdz 1,1");
check("Rdz 1,1 text", verseText(gen11) === "Na początku Bóg stworzył niebo i ziemię.",
  verseText(gen11) || "unresolved");
const mt514 = resolve("Mt 5,14");
check("Mt 5,14 text", verseText(mt514) && verseText(mt514).indexOf("Wy jesteście światłem") >= 0,
  verseText(mt514) || "unresolved");
const mk99 = resolve("Mk 9,9");
check("Mk 9,9 split back out of verse 8", verseText(mk99) && verseText(mk99).indexOf("A gdy schodzili z góry") === 0,
  verseText(mk99) || "unresolved");
check("Mk 9,8 keeps only its own text",
  verseText(resolve("Mk 9,8")) === "I zaraz potem, gdy się rozejrzeli, nikogo już nie widzieli przy sobie, tylko samego Jezusa.",
  verseText(resolve("Mk 9,8")) || "unresolved");
const na23 = resolve("Na 2,3");
check("Na 2,3 is in order", verseText(na23) && verseText(na23).indexOf("Bo przywrócił Pan świetność") >= 0,
  verseText(na23) || "unresolved");
const na22 = resolve("Na 2,2");
check("Na 2,2 is in order", verseText(na22) && verseText(na22).indexOf("Pogromca") >= 0,
  verseText(na22) || "unresolved");
// Est 5 prints its opening twice: a short 1-2, then 1-2 again carrying the
// Greek-text expansion, then 3-14. The later copy wins, leaving the canonical
// 14 verses with the longer text.
const est51 = verseText(resolve("Est 5,1")) || "";
check("Est 5,1 is the expanded text, not the short duplicate",
  est51.indexOf("Trzeciego dnia, gdy skończyła się modlić") >= 0, est51.slice(0, 80));
check("Est 5,2 is the expanded text, not the short duplicate",
  (verseText(resolve("Est 5,2")) || "").indexOf("Ujrzałam cię, panie") >= 0);
check("Est 5 keeps 14 verses", byId.Est.chapters[4].verses.length === 14,
  String(byId.Est.chapters[4].verses.length));
check("Est 5,3 onwards is unshifted",
  (verseText(resolve("Est 5,3")) || "").indexOf("I rzekł król do niej") >= 0);
const outOfRange = resolve("J 999,1");
check("chapter past the end rejected", outOfRange === null);
check("every book resolves chapter 1", doc.books.every((book) => {
  const chapter = book.chapters[0];
  return chapter && chapter.verses.length > 0;
}));

console.log("search");
const love = Model.search(verses, "miłość", 10);
check("diacritic-insensitive search finds miłość", love.length > 0);
check("folded query works", Model.search(verses, "milosc", 10).length === love.length);
// J 3,16 says "umiłował", not "miłość", so a miłość search must not pretend to
// find it — folding maps ł to l, it does not stem.
check("J 3,16 is not a miłość hit (it says umiłował)",
  !love.some((v) => v.book === "J" && v.chapter === 3 && v.verse === 16));
const umilowal = Model.search(verses, "umiłował", 400);
check("umiłował finds J 3,16",
  umilowal.some((v) => v.book === "J" && v.chapter === 3 && v.verse === 16));
check("umilowal and umiłował agree",
  umilowal.length === Model.search(verses, "umilowal", 400).length);
check("miłość finds 1 J 4,8",
  love.some((v) => v.book === "1J" && v.chapter === 4 && v.verse === 8) ||
  Model.search(verses, "miłość", 400).some((v) => v.book === "1J" && v.chapter === 4 && v.verse === 8));
check("every miłość hit really contains the folded word",
  Model.search(verses, "miłość", 400).every((v) => v.folded.indexOf("milosc") >= 0));
check("search honours its limit", Model.search(verses, "Pan", 5).length === 5);
check("results carry reference fields", love.every((v) => v.book && v.chapter >= 1 && v.verse >= 1));
const shepherd = Model.search(verses, "moim pasterzem", 5);
check("phrase search finds Ps 23,1",
  shepherd.length > 0 && shepherd[0].book === "Ps" && shepherd[0].verse === 1,
  shepherd.length ? shepherd[0].book + " " + shepherd[0].verse : "none");
const world = Model.search(verses, "światłem świata", 5);
check("multi-term AND search", world.every((v) => v.folded.indexOf("swiatlem") >= 0 && v.folded.indexOf("swiata") >= 0));
const empty = Model.search(verses, "   ", 10);
check("blank query returns nothing", empty.length === 0);
const nonsense = Model.search(verses, "xyzzyqwerty", 10);
check("no-match query returns nothing", nonsense.length === 0);
check("prefix does not match mid-word", Model.search(verses, "mnie", 200).every((v) => v.folded.indexOf(" mnie") >= 0 || v.folded.indexOf("mnie") === 0));

console.log("daily verse");
const day = new Date(2026, 0, 1);
const first = Model.dailyReference(day);
check("daily reference is stable", JSON.stringify(Model.dailyReference(new Date(2026, 0, 1))) === JSON.stringify(first));
check("daily reference advances with the date",
  JSON.stringify(Model.dailyReference(new Date(2026, 0, 2))) !== JSON.stringify(first));
check("daily reference resolves", (() => {
  const ref = Model.dailyReference(day);
  const book = byId[ref.book];
  if (!book) return false;
  const chapter = book.chapters[ref.chapter - 1];
  return !!chapter && chapter.verses.length >= ref.verse;
})());
check("day 1 of a year is day 1", Model.dayOfYear(new Date(2026, 0, 1)) === 0);
check("day of year rolls over", Model.dayOfYear(new Date(2027, 0, 1)) === 0);

// Every day's verse must exist in the bundled text, in every book of the
// translation and under the source's own versification. Two entries were wrong
// once already: "Lk" instead of "Łk", and Joel's outpouring of the Spirit, which
// this site numbers Jl 3,1 rather than Jl 2,28.
const unresolvable = [];
for (let day = 0; day < 366; day += 1) {
  const date = new Date(2026, 0, 1 + day);
  const ref = Model.dailyReference(date);
  const book = byId[ref.book];
  if (!book) {
    unresolvable.push(date.toDateString() + " unknown book " + ref.book);
    continue;
  }
  const chapter = book.chapters[ref.chapter - 1];
  if (!chapter || !chapter.verses.some((v) => v.v === ref.verse)) {
    unresolvable.push(date.toDateString() + " missing " +
      Model.reference(ref.book, ref.chapter, ref.verse));
  }
}
check("every day of the year resolves to a real verse", unresolvable.length === 0,
  unresolvable.slice(0, 6).join("; "));

console.log("reference formatting");
check("formats a verse", Model.reference("J", 3, 16) === "J 3,16");
check("formats a chapter", Model.reference("1Kor", 13, 0) === "1Kor 13");
check("formats a book", Model.reference("Ps", 0, 0) === "Ps");
check("formats nothing", Model.reference("", 0, 0) === "");

console.log("");
if (failures) {
  console.log(failures + " failing check(s)");
  process.exit(1);
}
console.log("all checks passed");