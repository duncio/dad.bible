// Exercises Panel.qml's key handling and navigation by calling handleKey() with
// synthetic events, so the shortcuts are covered without a compositor.
//
//   qs -p tests/test-panel.qml
//
// The panel needs a bar to lay itself out against, so a stub stands in; none of
// its members are read outside the button and the popup, and the popup is never
// opened here.

import QtQuick
import Quickshell

Item {
  id: root
  width: 100
  height: 100

  property int failures: 0
  property int checks: 0

  readonly property string pluginDir: Quickshell.env("BIBLE_PLUGIN_DIR")
    || (Quickshell.env("HOME") + "/.config/omarchy/plugins/dad.bible")

  readonly property QtObject stubBar: QtObject {
    property bool vertical: false
    property int barSize: 26
    property int barH: 26
    property int barW: 1920
    property string position: "top"
    property color barForeground: "#ffffff"
    property string fontFamily: "sans"
    property var activePopout: null
    property var clickTargets: []
    function requestPopout(key) {}
    function releasePopout(key) {}
    function hideTooltip(item) {}
    function registerClickTarget(item) {}
    function unregisterClickTarget(item) {}
  }

  Loader {
    id: loader
    source: "file://" + root.pluginDir + "/Panel.qml"
    onLoaded: {
      item.bar = root.stubBar
      // Bookmarks go to a scratch file so a test run never touches the real store.
      if (item.bible) {
        item.bible.bookmarkPath = Quickshell.statePath("omarchy/dad.bible-test/bookmarks.json")
      }
    }
  }

  readonly property var panel: loader.item

  // A stand-in for a Qt key event: handleKey only reads key, modifiers and
  // accepted.
  function key(code, modifiers) {
    return { key: code, modifiers: modifiers || 0, accepted: false }
  }

  // Modifier masks, named for how they read at the call sites below.
  readonly property int none: 0
  readonly property int ctrl: Qt.ControlModifier
  readonly property int shift: Qt.ShiftModifier

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
    interval: 3000
    running: loader.status === Loader.Ready || loader.status === Loader.Error
    repeat: false
    onTriggered: root.run()
  }

  Connections {
    target: loader
    function onStatusChanged() {
      if (loader.status === Loader.Error) {
        console.log("FAIL Panel.qml failed to load")
        Qt.exit(1)
      }
    }
  }

  function run() {
    var panel = root.panel
    if (!panel || !panel.bible || !panel.bible.loaded) {
      console.log("FAIL panel loaded its text — service.loaded is " +
        (panel && panel.bible ? String(panel.bible.loaded) : "no service"))
      Qt.exit(1)
      return
    }

    console.log("opening on a known verse")
    panel.goTo({ book: "J", chapter: 3, verse: 16 })
    check("lands on the verse asked for", panel.chapterVerse === 16 && panel.book === "J")
    check("reference reads back", panel.reference() === "J 3,16", panel.reference())

    console.log("verse stepping")
    panel.handleKey(root.key(Qt.Key_Down, root.none))
    check("Down steps to the next verse", panel.chapterVerse === 17, String(panel.chapterVerse))
    panel.handleKey(root.key(Qt.Key_Up, root.none))
    check("Up steps back", panel.chapterVerse === 16, String(panel.chapterVerse))
    panel.handleKey(root.key(Qt.Key_Return, root.none))
    check("Enter with no query advances the verse", panel.chapterVerse === 17, String(panel.chapterVerse))

    console.log("chapters")
    panel.handleKey(root.key(Qt.Key_N, root.ctrl))
    check("Ctrl+N opens the next chapter", panel.chapterNumber === 4, String(panel.chapterNumber))
    check("Ctrl+N keeps the verse where it fits", panel.chapterVerse === 17, String(panel.chapterVerse))
    panel.handleKey(root.key(Qt.Key_P, root.ctrl))
    check("Ctrl+P returns", panel.chapterNumber === 3, String(panel.chapterNumber))

    console.log("bookmarks")
    panel.handleKey(root.key(Qt.Key_B, root.ctrl))
    check("Ctrl+B bookmarks the verse", panel.bible.isBookmarked("J", 3, 17) === true)
    check("Ctrl+B reports what it did", panel.status.indexOf("Dodano") === 0, panel.status)
    panel.handleKey(root.key(Qt.Key_B, root.ctrl))
    check("Ctrl+B again removes it", panel.bible.isBookmarked("J", 3, 17) === false)
    check("removal is reported", panel.status.indexOf("Usunięto") === 0, panel.status)

    console.log("queries")
    panel.query = "J 3,16"
    check("a reference query resolves to one result",
      panel.results.length === 1 && panel.results[0].verse === 16,
      String(panel.results.length))
    panel.handleKey(root.key(Qt.Key_Return, root.none))
    check("Enter on a reference opens it", panel.chapterVerse === 16 && panel.query === "",
      panel.reference() + " query=" + JSON.stringify(panel.query))

    panel.query = "miłość"
    var results = panel.results.length
    check("a word query finds verses", results > 10, String(results))
    panel.handleKey(root.key(Qt.Key_Down, root.none))
    check("Down in results activates the cursor", panel.cursorActive === true)
    var chosen = panel.cursor
    check("the cursor starts at the top hit", chosen === 0, String(chosen))
    panel.handleKey(root.key(Qt.Key_Down, root.none))
    check("Down moves the cursor", panel.cursor === 1, String(panel.cursor))
    // Capture what was on screen before Enter replaced the query.
    var target = panel.results[panel.cursor]
    panel.handleKey(root.key(Qt.Key_Return, root.none))
    check("Enter opens the highlighted result",
      panel.book === target.book && panel.chapterNumber === target.chapter
      && panel.chapterVerse === target.verse,
      "got " + panel.book + "/" + panel.chapterNumber + "/" + panel.chapterVerse
      + " want " + target.book + "/" + target.chapter + "/" + target.verse)
    check("opening a result clears the query", panel.query === "", JSON.stringify(panel.query))

    console.log("escape")
    panel.query = "miłość"
    panel.handleKey(root.key(Qt.Key_Escape, root.none))
    check("Esc clears the query", panel.query === "", JSON.stringify(panel.query))

    console.log("unbound keys")
    var space = root.key(Qt.Key_Space, root.none)
    panel.handleKey(space)
    check("Space is left to the field", space.accepted === false)
    var letter = root.key(Qt.Key_J, root.none)
    panel.handleKey(letter)
    check("a letter is left to the field", letter.accepted === false)
    var ctrlC = root.key(Qt.Key_C, root.ctrl)
    panel.handleKey(ctrlC)
    check("an unbound Ctrl combination is left alone", ctrlC.accepted === false)

    console.log("daily verse")
    panel.goTo({ book: "Rdz", chapter: 1, verse: 1 })
    panel.handleKey(root.key(Qt.Key_D, root.ctrl))
    var daily = panel.bible.dailyReference(new Date())
    check("Ctrl+D opens the day's verse",
      panel.book === daily.book && panel.chapterNumber === daily.chapter,
      "got " + panel.book + "/" + panel.chapterNumber + " want " + daily.book + "/" + daily.chapter)

    // The bar label must be driven by the clock, not by `new Date()`. A binding
    // on `new Date()` evaluates once and never again, so on a shell left running
    // the label would still show the day the plugin loaded on. Today's value
    // cannot catch that — at load time the frozen and correct answers agree — so
    // this stands the panel on a different day and checks the label follows it.
    check("the label is not the shell's wall-clock date",
      panel.today instanceof Date && !!panel.today.getFullYear(),
      "today is " + panel.today)
    check("the label matches the day's verse for today",
      panel.current.label === panel.bible.dailyReference(panel.today).label,
      "label " + panel.current.label)

    var tomorrow = new Date(panel.today.getFullYear(), panel.today.getMonth(),
      panel.today.getDate() + 1)
    var tomorrowVerse = panel.bible.dailyReference(tomorrow)
    panel.today = tomorrow
    check("the label follows the day",
      panel.current.label === tomorrowVerse.label,
      "label " + panel.current.label + " want " + tomorrowVerse.label)
    check("the rotation really does change day to day",
      tomorrowVerse.label !== daily.label,
      daily.label + " vs " + tomorrowVerse.label)

    // Ctrl+D must read the same day as the label, or the two disagree at midnight.
    panel.goTo({ book: "Rdz", chapter: 1, verse: 1 })
    panel.handleKey(root.key(Qt.Key_D, root.ctrl))
    check("Ctrl+D follows the day too",
      panel.book === tomorrowVerse.book && panel.chapterNumber === tomorrowVerse.chapter,
      "landed on " + panel.reference() + " want " + tomorrowVerse.label)
    panel.today = new Date()

    console.log("out of range")
    var before = panel.chapterNumber
    panel.goTo({ book: "J", chapter: 999, verse: 1 })
    check("a chapter past the end is refused", panel.chapterNumber === before,
      "moved to " + panel.reference() + " from " + before)
    check("the refusal is explained", panel.status.indexOf("nie ma takiego") > 0, panel.status)

    panel.bible.clearBookmarks()
    console.log("")
    if (root.failures) {
      console.log(root.failures + " failing check(s) of " + root.checks)
    } else {
      console.log("all " + root.checks + " checks passed")
    }
    Qt.exit(root.failures ? 1 : 0)
  }
}
