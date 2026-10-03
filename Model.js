// Reference parsing, Polish text folding, and search over Biblia Tysiaciecia.
//
// Pure JS with no QML dependency so it can be exercised by tests/test-model.js
// under plain node.

// Canonical book ids, in canonical order, with the catalogue abbreviation, the
// full Polish name, and the aliases people actually type. Folded at load so
// lookups never have to re-fold user input.
const BOOK_DEFS = [
  ["Rdz", "Księga Rodzaju", ["rdz", "rodzaju", "gen", "genesis", "1 moj", "1moj", "pismo"]],
  ["Wj", "Księga Wyjścia", ["wj", "wyjscia", "wyj", "eks", "2 moj", "2moj"]],
  ["Kpł", "Księga Kapłańska", ["kpl", "kaplanska", "kap", "lew", "3 moj", "3moj"]],
  ["Lb", "Księga Liczbowa", ["lb", "liczbowa", "licz", "4 moj", "4moj"]],
  ["Pwt", "Księga Powtórzonego Prawa", ["pwt", "powtorzonego", "powt", "prawa", "5 moj", "5moj"]],
  ["Joz", "Księga Jozuego", ["joz", "jozuego", "jos", "6 moj", "6moj"]],
  ["Sdz", "Księga Sędziów", ["sdz", "sedziow", "sędz", "sed", "7 moj", "7moj"]],
  ["Rt", "Księga Rut", ["rt", "rut"]],
  ["1Sm", "Pierwsza Księga Samuela", ["1sm", "1 sm", "sm", "samuela", "1 sam", "1sam", "1s"]],
  ["2Sm", "Druga Księga Samuela", ["2sm", "2 sm", "2 sam", "2sam", "2s"]],
  ["1Krl", "Pierwsza Księga Królew", ["1krl", "1 krl", "krl", "krolew", "3 krl", "3krl"]],
  ["2Krl", "Druga Księga Królew", ["2krl", "2 krl", "4 krl", "4krl"]],
  ["1Krn", "Pierwsza Księga Kronik", ["1krn", "1 krn", "krn", "kronik", "1 kron", "1kron"]],
  ["2Krn", "Druga Księga Kronik", ["2krn", "2 krn", "2 kron", "2kron"]],
  ["Ezd", "Księga Ezdrasza", ["ezd", "ezdrasza", "ezdr"]],
  ["Ne", "Księga Neemiasza", ["ne", "neemiasza", "nem"]],
  ["Tb", "Księga Tobita", ["tb", "tobita", "tobi"]],
  ["Jdt", "Księga Judyty", ["jdt", "judyty", "judy"]],
  ["Est", "Księga Estery", ["est", "estery", "ester"]],
  ["1Mch", "Pierwsza Księga Machabeusza", ["1mch", "1 mch", "mch", "machabeusza", "1 mach", "1mach"]],
  ["2Mch", "Druga Księga Machabeusza", ["2mch", "2 mch", "2 mach", "2mach"]],
  ["Hi", "Księga Hioba", ["hi", "hioba", "hiob", "job"]],
  ["Ps", "Księga Psalmów", ["ps", "psalmow", "psalm", "psa"]],
  ["Prz", "Księga Przysłówiec", ["prz", "przyslowiec", "przysl", "przeds"]],
  ["Koh", "Księga Kohelet", ["koh", "kohelet", "kohel"]],
  ["Pnp", "Pieśń Pieśni", ["pnp", "piesn piesni", "piesń", "piesn", "pp"]],
  ["Mdr", "Księga Mądrości", ["mdr", "madrosci", "madr"]],
  ["Syr", "Księga Syracha", ["syr", "syrach", "sirach"]],
  ["Iz", "Księga Izajasza", ["iz", "izajasza", "izj"]],
  ["Jr", "Księga Jeremiasza", ["jr", "jeremiasza", "jrm"]],
  ["Lm", "Księga Lamentacji", ["lm", "lamentacji", "lament", "treny"]],
  ["Ba", "Księga Barucha", ["ba", "barucha"]],
  ["Ez", "Księga Ezechiela", ["ez", "ezechiela", "ezk"]],
  ["Dn", "Księga Daniela", ["dn", "daniela", "dan"]],
  ["Oz", "Księga Ozeasza", ["oz", "ozeasza", "ozj"]],
  ["Jl", "Księga Joela", ["jl", "joela", "joe"]],
  ["Am", "Księga Amosa", ["am", "amosa"]],
  ["Ab", "Księga Abdiasza", ["ab", "abdiasza", "abd"]],
  ["Jon", "Księga Jonasza", ["jon", "jonasza"]],
  ["Mi", "Księga Micheasza", ["mi", "micheasza", "mich"]],
  ["Na", "Księga Nahuma", ["na", "nahuma", "nah"]],
  ["Ha", "Księga Habakuka", ["ha", "habakuka", "hab"]],
  ["So", "Księga Sofoniasza", ["so", "sofoniasza", "sof"]],
  ["Ag", "Księga Aggeusza", ["ag", "aggeusza", "agg"]],
  ["Za", "Księga Zachariasza", ["za", "zachariasza", "zach"]],
  ["Ml", "Księga Malachiasza", ["ml", "malachiasza", "mal"]],
  ["Mt", "Ewangelia według św. Mateusza", ["mt", "mateusza", "mateusz", "mat", "ew", "ewangelia"]],
  ["Mk", "Ewangelia według św. Marka", ["mk", "marka", "marek", "mar"]],
  ["Łk", "Ewangelia według św. Łukasza", ["lk", "luk", "luki", "luka", "lukasza"]],
  ["J", "Ewangelia według św. Jana", ["j", "jan", "jana", "jan chrzciciel", "jch", "j an"]],
  ["Dz", "Dzieje Apostołów", ["dz", "dzjeje", "dz apostolow", "dzap", "apostolow", "dzieje"]],
  ["Rz", "List do Rzymian", ["rz", "rzymian", "rom"]],
  ["1Kor", "Pierwszy List do Koryntian", ["1kor", "1 kor", "kor", "koryntian", "1 koryntian"]],
  ["2Kor", "Drugi List do Koryntian", ["2kor", "2 kor", "2 koryntian"]],
  ["Ga", "List do Galatów", ["ga", "galatow", "gal"]],
  ["Ef", "List do Efezjan", ["ef", "efezjan", "efez"]],
  ["Flp", "List do Filipian", ["flp", "filipian", "fil"]],
  ["Kol", "List do Kolosian", ["kol", "kolosian", "kolos"]],
  ["1Tes", "Pierwszy List do Tesaliczan", ["1tes", "1 tes", "tes", "tesaliczan", "1 tesaliczan"]],
  ["2Tes", "Drugi List do Tesaliczan", ["2tes", "2 tes", "2 tesaliczan"]],
  ["1Tm", "Pierwszy List do Tymoteusza", ["1tm", "1 tm", "tm", "tymoteusza", "1 tymoteusza"]],
  ["2Tm", "Drugi List do Tymoteusza", ["2tm", "2 tm", "2 tymoteusza"]],
  ["Tt", "List do Tytusa", ["tt", "tytusa", "tyt"]],
  ["Flm", "List do Filemona", ["flm", "filemona", "filem"]],
  ["Hbr", "List do Hebrajczyków", ["hbr", "hebrajczykow", "heb", "hebr"]],
  ["Jk", "List Jakuba", ["jk", "jakuba", "jakub"]],
  ["1P", "Pierwszy List Piotrowy", ["1p", "1 p", "piotr", "piotrowy", "1 piotrowy"]],
  ["2P", "Drugi List Piotrowy", ["2p", "2 p", "2 piotrowy"]],
  ["1J", "Pierwszy List Jana", ["1j", "1 j", "1 jana", "1jan"]],
  ["2J", "Drugi List Jana", ["2j", "2 j", "2 jana", "2jan"]],
  ["3J", "Trzeci List Jana", ["3j", "3 j", "3 jana", "3jan"]],
  ["Jud", "List Judy", ["jud", "juda", "judy"]],
  ["Ap", "Objawienie Apokalipsy", ["ap", "apokalipsy", "objawienie", "obj"]]
];

// Letters that carry diacritics in Polish and other Latin texts, so "milosc"
// finds "miłość". Anything unmapped is left alone.
const FOLD_MAP = {
  "ą": "a", "ć": "c", "ę": "e", "ł": "l", "ń": "n", "ó": "o", "ś": "s", "ź": "z", "ż": "z",
  "â": "a", "ä": "a", "ã": "a", "å": "a", "ă": "a", "ā": "a",
  "ç": "c", "č": "c",
  "ď": "d", "đ": "d", "ð": "d",
  "è": "e", "é": "e", "ê": "e", "ë": "e", "ē": "e", "ě": "e",
  "ĝ": "g", "ğ": "g",
  "î": "i", "ï": "i", "ī": "i", "í": "i", "ì": "i",
  "ñ": "n", "ň": "n",
  "ô": "o", "ö": "o", "õ": "o", "ø": "o", "ō": "o",
  "ř": "r", "ŕ": "r",
  "ş": "s", "š": "s", "ș": "s",
  "ť": "t", "ț": "t", "þ": "t",
  "ù": "u", "ú": "u", "û": "u", "ü": "u", "ū": "u", "ů": "u",
  "ý": "y", "ÿ": "y",
  "ź": "z", "ž": "z", "ż": "z",
  "ß": "ss",
  "'": " ", "’": " ", "`": " ", "«": " ", "»": " ", "-": " ", "–": " ", "—": " "
};

// Built with each key escaped: a raw "-" between two other keys would be read as
// a character range and silently stop matching hyphens.
const FOLD_RE = new RegExp(
  "[" + Object.keys(FOLD_MAP).map(function (ch) { return "\\" + ch; }).join("") + "]",
  "g"
);

function fold(value) {
  return String(value === undefined || value === null ? "" : value)
    .toLowerCase()
    .replace(FOLD_RE, function (ch) { return FOLD_MAP[ch]; })
    .replace(/\s+/g, " ")
    .trim();
}

// Alias -> book id, plus longest-first so "1 kor" wins over "k" and a bare "j"
// never shadows "1j".
const ALIASES = (function () {
  const map = Object.create(null);
  const list = [];
  for (let i = 0; i < BOOK_DEFS.length; i++) {
    const id = BOOK_DEFS[i][0];
    const name = BOOK_DEFS[i][1];
    const aliases = BOOK_DEFS[i][2] || [];
    const all = [id].concat(aliases, [name]);
    for (let a = 0; a < all.length; a++) {
      const key = fold(all[a]);
      if (!key) continue;
      if (map[key] === undefined) {
        map[key] = id;
        list.push(key);
      }
    }
  }
  list.sort(function (a, b) { return b.length - a.length; });
  return { map: map, keys: list };
})();

const BOOK_NAMES = (function () {
  const map = Object.create(null);
  for (let i = 0; i < BOOK_DEFS.length; i++) map[BOOK_DEFS[i][0]] = BOOK_DEFS[i][1];
  return map;
})();

const BOOK_IDS = BOOK_DEFS.map(function (def) { return def[0]; });
const NEW_TESTAMENT_FROM = BOOK_IDS.indexOf("Mt");

function bookName(id) {
  return BOOK_NAMES[id] || id;
}

function isNewTestament(id) {
  return BOOK_IDS.indexOf(id) >= NEW_TESTAMENT_FROM;
}

// "J 3,16" / "j3,16" / "1 kor 13,4-7" / "ps 23" -> { book, chapter, verse, end }
// or null when the text is not a reference at all.
function parseReference(input) {
  // fold() turns "-" into a space (so a search for "mój-bóg" hits "mój bóg"),
  // which would destroy a verse range. Park such a dash on a control character
  // fold() leaves alone, then put it back.
  var DASH = "\u0001";
  var raw = String(input === undefined || input === null ? "" : input)
    .replace(/(\d)\s*[-–—]\s*(?=\d)/g, "$1" + DASH);
  var text = fold(raw).split(DASH).join("-").replace(/\s+/g, " ");
  if (!text) return null;

  var book = null;
  var rest = "";
  for (var i = 0; i < ALIASES.keys.length; i++) {
    var key = ALIASES.keys[i];
    if (text === key) {
      book = ALIASES.map[key];
      rest = "";
      break;
    }
    if (text.indexOf(key) === 0 && /^[\s\d]/.test(text.charAt(key.length))) {
      book = ALIASES.map[key];
      rest = text.slice(key.length).replace(/^\s+/, "");
      break;
    }
  }
  if (!book) return null;

  if (!rest) return { book: book, chapter: 0, verse: 0, end: 0 };

  var m = /^(\d+)\s*(?:[.,:]\s*(\d+))?\s*(?:[-–]\s*(\d+))?/.exec(rest);
  if (!m) return null;
  var chapter = parseInt(m[1], 10);
  var verse = m[2] ? parseInt(m[2], 10) : 0;
  var end = m[3] ? parseInt(m[3], 10) : 0;
  if (end && verse && end < verse) {
    var swap = verse;
    verse = end;
    end = swap;
  }
  return { book: book, chapter: chapter, verse: verse, end: end };
}

function reference(book, chapter, verse) {
  if (!book) return "";
  var text = book;
  if (chapter) {
    text += " " + chapter;
    if (verse) text += "," + verse;
  }
  return text;
}

// Whole-word prefix match on the folded needle, so "mi" does not light up
// "mnie" mid-word but "miło" does match "miłość".
function wordPrefixMatch(haystack, needle) {
  var from = 0;
  while (from <= haystack.length) {
    var at = haystack.indexOf(needle, from);
    if (at < 0) return false;
    var before = at === 0 ? " " : haystack.charAt(at - 1);
    if (before === " ") return true;
    from = at + 1;
  }
  return false;
}

// Search the flat verse list. Every term must appear somewhere in the verse
// (AND), scored so that whole-word hits and short verses rank higher.
function search(verses, query, limit) {
  var terms = fold(query).split(" ").filter(function (t) { return t.length > 0; });
  if (!terms.length || !verses) return [];

  var max = limit || 60;
  var hits = [];
  for (var i = 0; i < verses.length; i++) {
    var verse = verses[i];
    var text = verse.folded;
    var all = true;
    var score = 0;
    for (var t = 0; t < terms.length; t++) {
      var term = terms[t];
      if (text.indexOf(term) < 0) {
        all = false;
        break;
      }
      // A whole-word hit is the strong one; a mid-word hit only counts a little.
      score += wordPrefixMatch(text, term) ? 6 : 1;
    }
    if (!all) continue;
    hits.push({ index: i, score: score, length: verse.text.length });
  }

  // Whole-word hits first, then the most compact verse: among equally relevant
  // verses the shorter one is the more direct answer. Canon order breaks the
  // remaining ties so results stay stable between searches.
  hits.sort(function (a, b) {
    if (b.score !== a.score) return b.score - a.score;
    if (a.length !== b.length) return a.length - b.length;
    return a.index - b.index;
  });
  return hits.slice(0, max).map(function (hit) { return verses[hit.index]; });
}

// One verse per day, stable across restarts: day-of-year picks the entry, so
// the same day always shows the same verse and the rotation never repeats
// inside a single pass through the list.
const DAILY = [
  ["J", 3, 16], ["Ps", 23, 1], ["Prz", 3, 5], ["Mt", 5, 14], ["Rdz", 1, 1],
  ["Iz", 40, 31], ["Flp", 4, 13], ["Rz", 8, 28], ["1Kor", 13, 4], ["J", 14, 6],
  ["Ps", 119, 105], ["Koh", 3, 1], ["Mt", 6, 33], ["J", 8, 12], ["1Kor", 15, 13],
  ["Ps", 46, 2], ["Hi", 19, 25], ["2Tm", 1, 7], ["Łk", 12, 6], ["Mdr", 3, 2],
  ["Rdz", 3, 15], ["Ps", 121, 1], ["Jl", 3, 1], ["1Kor", 16, 13], ["Ef", 2, 8],
  ["J", 15, 5], ["Ps", 51, 12], ["Jr", 29, 11], ["Mt", 11, 28], ["Iz", 53, 5],
  ["Rdz", 15, 6], ["Ps", 118, 6], ["1J", 4, 8], ["Flp", 2, 14], ["Ml", 3, 1],
  ["J", 11, 25], ["Ps", 37, 5], ["1Kor", 10, 31], ["Za", 12, 10], ["Mt", 7, 7],
  ["Ps", 16, 8], ["Prz", 11, 2], ["J", 1, 14], ["Iz", 43, 2], ["Dz", 17, 28],
  ["1Kor", 12, 8], ["Rdz", 2, 7], ["Ps", 136, 1], ["Mdr", 7, 14], ["J", 13, 34],
  ["1Kor", 13, 8], ["Ps", 103, 1], ["Lm", 3, 22], ["Mk", 10, 27], ["Iz", 41, 10]
];

function dayOfYear(date) {
  var start = new Date(date.getFullYear(), 0, 1);
  var today = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  return Math.floor((today - start) / 86400000);
}

function dailyReference(date) {
  var entry = DAILY[dayOfYear(date) % DAILY.length];
  return { book: entry[0], chapter: entry[1], verse: entry[2] };
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    BOOK_IDS: BOOK_IDS,
    BOOK_NAMES: BOOK_NAMES,
    fold: fold,
    bookName: bookName,
    isNewTestament: isNewTestament,
    parseReference: parseReference,
    reference: reference,
    search: search,
    dailyReference: dailyReference,
    dayOfYear: dayOfYear
  };
}