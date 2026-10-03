// Exercises Service.qml against the bundled bible.json: loading, reference
// lookup, search, daily verse, verse stepping and bookmarks.
//
//   qs -p tests/test-root.service.qml
//
// Prints one line per check and exits non-zero (via a red banner) if any fail.
// Pair it with tests/test-model.js, which covers the parsing in Model.js.

import QtQuick
import Quickshell

Item {
  id: root
  width: 100
  height: 100

  property int failures: 0
  property int checks: 0

  // A standalone qs run blackholes every URL, including this file's own, so a
  // relative source cannot be resolved here the way the shell resolves it. The
  // plugin directory comes from the environment instead; override it with
  // BIBLE_PLUGIN_DIR when testing a copy elsewhere.
  readonly property string pluginDir: Quickshell.env("BIBLE_PLUGIN_DIR")
    || (Quickshell.env("HOME") + "/.config/omarchy/plugins/dad.bible")

  Loader {
    id: loader
    source: "file://" + root.pluginDir + "/Service.qml"
    // Bookmarks go to a scratch file so a test run never touches the real store.
    onLoaded: item.bookmarkPath = Quickshell.statePath("omarchy/dad.bible-test/bookmarks.json")
  }

  readonly property var service: loader.item

  function check(name, condition, detail) {
    checks += 1
    if (!condition) {
      failures += 1
      console.log("FAIL " + name + (detail ? " — " + detail : ""))
    } else {
      console.log("ok   " + name)
    }
  }

  Timer {
    interval: 2500
    running: loader.status === Loader.Ready || loader.status === Loader.Error
    repeat: false
    onTriggered: root.run()
  }

  // A parse failure in Service.qml leaves nothing to test.
  Connections {
    target: loader
    function onStatusChanged() {
      if (loader.status === Loader.Error) {
        console.log("FAIL Service.qml failed to load: " + (loader.errorString || "?"))
        Qt.exit(1)
      }
    }
  }

  function run() {
    console.log("loading (status=" + loader.status + ", item=" + (loader.item === null ? "null" : "ok") + ")")
    check("loads without error", root.service.loadError === "", root.service.loadError)
    check("73 books", root.service.books.length === 73, String(root.service.books.length))
    check("translation recorded", root.service.translation === "Biblia Tysiąclecia V", root.service.translation)
    check("35k verses flattened", root.service.verses.length > 35000, String(root.service.verses.length))
    check("every verse carries folded text", root.service.verses.every(function (v) { return typeof v.folded === "string" }))

    check("verse text by number", root.service.verseText("J", 3, 16).indexOf("Jednorodzonego") >= 0)
    check("verse numbering skips are respected", root.service.verseText("1P", 4, 5) === "",
      JSON.stringify(root.service.verseText("1P", 4, 5)))
    check("chapter past the end is null", root.service.chapter("J", 999) === null)
    check("chapter count for J", root.service.chapterCount("J") === 21, String(root.service.chapterCount("J")))

    var byReference = root.service.search("J 3,16", 5)
    check("reference search", byReference.length === 1 && byReference[0].verse === 16)
    check("reference search is marked exact", byReference.length === 1 && byReference[0].exact === true)
    var chapterOnly = root.service.search("ps 23", 5)
    check("chapter-only reference resolves", chapterOnly.length === 1 && chapterOnly[0].book === "Ps"
      && chapterOnly[0].chapter === 23, JSON.stringify(chapterOnly))
    check("chapter-only reference is not marked exact",
      chapterOnly.length === 1 && chapterOnly[0].exact === false)
    check("text search finds verses", root.service.search("miłość", 60).length > 10)
    check("text search folds diacritics",
      root.service.search("milosc", 60).length === root.service.search("miłość", 60).length)
    check("no-match search is empty", root.service.search("qqqzzz", 60).length === 0)
    check("unknown book falls through to text search", root.service.search("nonsens 4,2", 60).length === 0)

    var daily = root.service.dailyReference(new Date(2026, 0, 1))
    check("daily verse resolves", !!root.service.verseText(daily.book, daily.chapter, daily.verse))
    check("daily verse is stable for a date",
      root.service.dailyReference(new Date(2026, 0, 1)).label === daily.label)
    check("daily verse moves with the date",
      root.service.dailyReference(new Date(2026, 0, 2)).label !== daily.label)
    check("daily verse label is formatted", daily.label.indexOf(",") > 0, daily.label)

    var stepped = root.service.step({ book: "J", chapter: 3, verse: 16 }, 1)
    check("step forward inside a chapter", stepped.verse === 17)
    var back = root.service.step({ book: "Rdz", chapter: 1, verse: 1 }, -1)
    check("step back past the first verse stops", back === null)
    var crossed = root.service.step({ book: "Mt", chapter: 28, verse: 20 }, 1)
    check("step forward crosses into the next book", crossed && crossed.book === "Mk",
      JSON.stringify(crossed))
    check("next chapter past the last is null", root.service.nextChapter("Ap", 22, 1) === null)
    check("previous chapter past the first is null", root.service.nextChapter("Rdz", 1, -1) === null)

    root.service.clearBookmarks()
    root.service.clearBookmarks()
    check("starts with no bookmarks", root.service.bookmarks.length === 0)
    check("adding reports true", root.service.toggleBookmark("J", 3, 16) === true)
    check("one bookmark after adding", root.service.bookmarks.length === 1,
      String(root.service.bookmarks.length))
    check("bookmarked verse is recognised", root.service.isBookmarked("J", 3, 16) === true)
    check("bookmark carries its text", root.service.bookmarks[0].text.indexOf("Jednorodzonego") >= 0)
    root.service.toggleBookmark("Ps", 23, 1)
    check("two bookmarks, newest first",
      root.service.bookmarks.length === 2 && root.service.bookmarks[0].key === "Ps 23,1",
      JSON.stringify(root.service.bookmarks.map(function (b) { return b.key })))
    check("@ lists the bookmarks", root.service.search("@", 40).length === 2)
    check("@ with a term filters", root.service.search("@j 3", 40).length === 1)
    check("not bookmarked", root.service.isBookmarked("Rdz", 1, 1) === false)
    check("removing reports false", root.service.toggleBookmark("J", 3, 16) === false)
    check("one bookmark left", root.service.bookmarks.length === 1,
      String(root.service.bookmarks.length))
    check("removed bookmark is gone", root.service.isBookmarked("J", 3, 16) === false)
    root.service.clearBookmarks()
    check("cleared", root.service.bookmarks.length === 0)

    console.log("")
    if (root.failures) {
      console.log(root.failures + " failing check(s) of " + root.checks)
    } else {
      console.log("all " + root.checks + " checks passed")
    }
    Qt.exit(root.failures ? 1 : 0)
  }
}
