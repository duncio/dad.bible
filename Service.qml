import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Owns the Bible text, the search index, and the bookmark store. The panel is a
// view over this; nothing here touches QML styling.
//
// data/bible.json is parsed once at startup into a flat verse list. Each verse
// carries a folded copy of its text (lowercase, diacritics gone) so search can
// run without touching the regexes per keystroke, and a "bookIndex*10000 +
// chapter*100 + verse" style key so bookmarks can be compared as strings.
Item {
  id: root

  property var settings: ({})

  property bool loaded: false
  property string loadError: ""
  property string translation: ""
  property string publisher: ""

  property var books: []
  property var verses: []
  // id -> book record, rebuilt on load so lookups stay O(1).
  property var bookById: ({})

  // Saved references as { key, book, chapter, verse, text, folded }, newest
  // first. The file on disk holds just the "J 3,16" strings.
  property var bookmarks: []
  // Writable so the test suite can point it at a scratch file instead of the real
// one; the shell never sets it.
property string bookmarkPath: Quickshell.statePath("omarchy/dad.bible/bookmarks.json")

  // ── loading ───────────────────────────────────────────────────────────────

  FileView {
    id: bibleFile
    path: Qt.resolvedUrl("data/bible.json").toString().replace(/^file:\/\//, "")
    printErrors: true
    onLoaded: root.ingest(bibleFile.text())
    onLoadFailed: root.fail("data/bible.json is missing — run scripts/build-bible.py in the plugin directory")
  }

  function fail(message) {
    loadError = message
    loaded = false
  }

  function ingest(raw) {
    var doc
    try {
      doc = JSON.parse(raw)
    } catch (error) {
      fail("data/bible.json is not valid JSON: " + error)
      return
    }
    if (!doc || !doc.books || !doc.books.length) {
      fail("data/bible.json has no books in it")
      return
    }

    var index = {}
    var flat = []
    for (var b = 0; b < doc.books.length; b++) {
      var book = doc.books[b]
      index[book.id] = book
      var chapters = book.chapters || []
      for (var c = 0; c < chapters.length; c++) {
        var chapter = chapters[c]
        var texts = chapter.verses || []
        for (var v = 0; v < texts.length; v++) {
          var entry = texts[v]
          var text = typeof entry === "string" ? entry : String(entry.t || "")
          flat.push({
            book: book.id,
            chapter: chapter.chapter,
            verse: typeof entry === "string" ? v + 1 : entry.v,
            text: text,
            folded: Model.fold(text),
            bookIndex: book.index
          })
        }
      }
    }

    books = doc.books
    bookById = index
    verses = flat
    translation = doc.translation || "Biblia Tysiąclecia V"
    publisher = doc.publisher || ""
    loadError = ""
    loaded = true
  }

  // ── lookup ────────────────────────────────────────────────────────────────

  function book(id) {
    return bookById[id] || null
  }

  function bookTitle(id) {
    var found = bookById[id]
    return found ? found.name : Model.bookName(id)
  }

  // Chapter as { chapter, verses: [{ v, t }] }, or null when out of range.
  function chapter(id, number) {
    var found = bookById[id]
    if (!found || !number) return null
    var chapters = found.chapters || []
    if (number < 1 || number > chapters.length) return null
    return chapters[number - 1]
  }

  function chapterCount(id) {
    var found = bookById[id]
    return found ? (found.chapters || []).length : 0
  }

  // Steps through the whole Bible, crossing book and chapter boundaries.
  function step(from, delta) {
    var current = chapter(from.book, from.chapter)
    if (!current) return null
    var list = current.verses || []
    var position = -1
    for (var i = 0; i < list.length; i++) {
      if (list[i].v === from.verse) {
        position = i
        break
      }
    }
    if (position < 0) position = 0
    position += delta
    if (position >= 0 && position < list.length) {
      return { book: from.book, chapter: from.chapter, verse: list[position].v }
    }
    return nextChapter(from.book, from.chapter, delta > 0 ? 1 : -1)
  }

  // Walks the canonical book order, crossing into the next or previous book at
  // either end. `verse` is carried over when the landing chapter is long enough
  // to have it; verse 0 means "whatever the panel picks", which is the chapter's
  // first verse.
  function nextChapter(id, number, delta, verse) {
    var list = books
    if (!list || !list.length) return null
    var position = -1
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        position = i
        break
      }
    }
    if (position < 0) return null

    var bookIndex = position
    var chapterIndex = number - 1 + (delta || 1)
    while (chapterIndex >= (list[bookIndex].chapters || []).length) {
      chapterIndex -= (list[bookIndex].chapters || []).length
      bookIndex += 1
      if (bookIndex >= list.length) return null
    }
    while (chapterIndex < 0) {
      bookIndex -= 1
      if (bookIndex < 0) return null
      chapterIndex += (list[bookIndex].chapters || []).length
    }

    var landed = list[bookIndex].id
    var target = chapter(landed, chapterIndex + 1)
    var wanted = 0
    if (verse && target) {
      var entries = target.verses || []
      for (var v = 0; v < entries.length; v++) {
        if (entries[v].v === verse) {
          wanted = verse
          break
        }
      }
      // The chapter is shorter than the verse we were on: land on its last line
      // rather than its first, which is closer to where the reading stopped.
      if (!wanted && entries.length) wanted = entries[entries.length - 1].v
    }
    return { book: landed, chapter: chapterIndex + 1, verse: wanted }
  }

  function previousChapter(id, number) {
    return nextChapter(id, number, -1)
  }

  function verseText(bookId, chapterNumber, verseNumber) {
    var found = chapter(bookId, chapterNumber)
    if (!found) return ""
    var list = found.verses || []
    for (var i = 0; i < list.length; i++) {
      if (list[i].v === verseNumber) return list[i].t
    }
    return ""
  }

  function isNewTestament(id) {
    return Model.isNewTestament(id)
  }

  // ── searching ─────────────────────────────────────────────────────────────

  // "@" narrows the list to saved bookmarks; anything else is a text search over
  // the whole Bible, unless it parses as a reference.
  function search(query, limit) {
    var trimmed = String(query === undefined || query === null ? "" : query).trim()
    if (!verses.length) return []

    // "@" lists the bookmarks, and what follows filters them by reference
    // ("@j 3"), not by verse text.
    if (trimmed.charAt(0) === "@") {
      var wanted = Model.fold(trimmed.slice(1))
      var found = []
      for (var i = 0; i < bookmarks.length; i++) {
        var entry = bookmarks[i]
        if (wanted && Model.fold(entry.key).indexOf(wanted) < 0) continue
        found.push(entry)
      }
      return found.slice(0, limit || 40)
    }

    var reference = Model.parseReference(trimmed)
    if (reference && bookById[reference.book]) {
      var found = chapter(reference.book, reference.chapter)
      if (!found) return []
      var entries = found.verses || []
      if (!entries.length) return []
      // A reference without a verse ("ps 23") stands for the whole chapter, so
      // the result shows its first verse.
      var wanted = reference.verse || entries[0].v
      var text = ""
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].v === wanted) {
          text = entries[i].t
          break
        }
      }
      if (!text) return []
      return [{
        book: reference.book,
        chapter: reference.chapter,
        verse: wanted,
        text: text,
        folded: Model.fold(text),
        exact: !!reference.verse
      }]
    }

    return Model.search(verses, trimmed, limit || 60)
  }

  // ── daily verse ───────────────────────────────────────────────────────────

  function dailyReference(when) {
    var reference = Model.dailyReference(when || new Date())
    var text = verseText(reference.book, reference.chapter, reference.verse)
    return {
      book: reference.book,
      chapter: reference.chapter,
      verse: reference.verse,
      text: text,
      label: Model.reference(reference.book, reference.chapter, reference.verse)
    }
  }

  // ── bookmarks ─────────────────────────────────────────────────────────────

  function referenceKey(bookId, chapterNumber, verseNumber) {
    return bookId + " " + chapterNumber + "," + verseNumber
  }

  function isBookmarked(bookId, chapterNumber, verseNumber) {
    var key = referenceKey(bookId, chapterNumber, verseNumber)
    for (var i = 0; i < bookmarks.length; i++) {
      if (bookmarks[i].key === key) return true
    }
    return false
  }

  function toggleBookmark(bookId, chapterNumber, verseNumber) {
    var key = referenceKey(bookId, chapterNumber, verseNumber)
    var next = bookmarks.slice()
    var at = -1
    for (var i = 0; i < next.length; i++) {
      if (next[i].key === key) {
        at = i
        break
      }
    }
    if (at >= 0) {
      next.splice(at, 1)
    } else {
      next.unshift(bookmarkEntry(key))
    }
    bookmarks = next
    persist()
    return at < 0
  }

  function bookmarkEntry(key) {
    var parsed = Model.parseReference(key) || { book: "", chapter: 0, verse: 0 }
    var text = verseText(parsed.book, parsed.chapter, parsed.verse)
    return {
      key: key,
      book: parsed.book,
      chapter: parsed.chapter,
      verse: parsed.verse,
      text: text,
      folded: Model.fold(text)
    }
  }

  function clearBookmarks() {
    bookmarks = []
    persist()
  }

  FileView {
    id: bookmarkFile
    path: root.bookmarkPath
    watchChanges: false
    printErrors: false
    onLoaded: root.loadBookmarks(text())
    onLoadFailed: root.bookmarks = []
  }

  // Only well-formed references are restored: a hand-edited or stale file
  // should not be able to break the panel.
  function loadBookmarks(raw) {
    var entries = []
    var parsed
    try {
      parsed = JSON.parse(raw)
    } catch (error) {
      parsed = []
    }
    if (Array.isArray(parsed)) {
      for (var i = 0; i < parsed.length; i++) {
        var key = parsed[i]
        if (typeof key === "string" && Model.parseReference(key)) entries.push(bookmarkEntry(key))
      }
    }
    bookmarks = entries
  }

  // A burst of toggles (holding a key, or a script) can outrun the write
  // process. The last payload is remembered and flushed once the running write
  // finishes, so the file always ends up holding the newest state.
  property string pendingJson: ""

  function persist() {
    var keys = []
    for (var i = 0; i < bookmarks.length; i++) keys.push(bookmarks[i].key)
    root.pendingJson = JSON.stringify(keys)
    if (!writer.running) writePending()
  }

  function writePending() {
    if (!root.pendingJson) return
    writer.json = root.pendingJson
    root.pendingJson = ""
    writer.running = true
  }

  // Written with printf and the JSON as a positional parameter: a saved
  // reference keeps its quotes and diacritics, and there is no stdin stream to
  // leave open.
  Process {
    id: writer
    property string json: "[]"
    command: [
      "bash", "-c",
      "mkdir -p \"$(dirname -- \"$1\")\" && printf '%s\\n' \"$2\" > \"$1\"",
      "_", root.bookmarkPath, writer.json
    ]
    onExited: root.writePending()
  }

  Component.onCompleted: {
    if (!bookmarkFile.loaded) bookmarkFile.reload()
  }
}