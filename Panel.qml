import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Biblia Tysiąclecia in the bar and in a panel: jump to a reference, read the
// chapter, search all 35k verses offline, and keep bookmarks.
//
// The panel is one text field and one list. Typing a reference ("J 3,16") jumps
// straight to it, anything else searches the whole Bible, and "@" lists the
// bookmarks. The bar label shows the day's verse.
Panel {
  id: root
  moduleName: "dad.bible"
  ipcTarget: "dad.bible"

  implicitWidth: bar ? (bar.vertical ? bar.barSize : button.implicitWidth) : button.implicitWidth
  implicitHeight: bar ? bar.barSize : 26

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Where the reading is: book id, chapter number, verse number.
  property string book: ""
  property int chapterNumber: 0
  property int chapterVerse: 0

  property string query: ""
  property int cursor: 0
  property bool cursorActive: false
  property string status: ""
  readonly property var results: service.loaded ? service.search(query, 60) : []

  // The day's verse, read from `today` rather than `new Date()`. A binding on
  // `new Date()` has no dependency to re-evaluate, so the label would stay on
  // whatever day the plugin happened to load on; SystemClock emits dateChanged at
  // each hour boundary, so midnight rolls the label over on a shell left running.
  // Hours is deliberate: it costs one signal an hour and cannot drift.
  readonly property var current: service.loaded ? service.dailyReference(root.today) : null

  readonly property bool showVerseInTooltip: boolSetting("showVerseInTooltip", true)

  function boolSetting(name, fallback) {
    var value = setting(name, fallback)
    if (typeof value === "string") return value !== "false"
    return value === undefined || value === null ? fallback : !!value
  }

  Service {
    id: service
    settings: root.settings
  }

  // The only reason this exists is to give the daily-verse binding something that
  // changes. See `current` above.
  SystemClock {
    id: clock
    precision: SystemClock.Hours
  }

  // The service, for the test suite, which drives the panel through this handle.
  readonly property var bible: service

  // Also for the test suite. Writable so the suite can stand on a different day
  // and prove the label follows it — which is the only way to tell a live binding
  // from a frozen one, since at load time both give the right answer. Assigning
  // replaces the clock binding for that instance only; the shell never writes it.
  property date today: clock.date

  function reference() {
    return Model.reference(root.book, root.chapterNumber, root.chapterVerse)
  }

  // A jump always lands on a real verse: a book alone lands on chapter 1, and a
  // chapter without a verse number selects that chapter's first verse, so the
  // bookmark shortcut always has something to act on.
  function goTo(target) {
    if (!target || !service.loaded || !target.book) return
    var wanted = target.chapter || 1
    var chapter = service.chapter(target.book, wanted)
    if (!chapter) {
      root.status = Model.reference(target.book, wanted, target.verse || 0) + " — nie ma takiego rozdziału"
      return
    }
    var verseNumber = target.verse || 0
    if (!verseNumber) {
      var list = chapter.verses || []
      verseNumber = list.length ? list[0].v : 0
    }
    root.book = target.book
    root.chapterNumber = wanted
    root.chapterVerse = verseNumber
    root.status = ""
  }

  function goToDaily() {
    if (!service.loaded) return
    // The same day the bar label reads, so Ctrl+D always lands on the verse the
    // label is showing.
    goTo(service.dailyReference(root.today))
  }

  // Enter on the field: a typed reference opens it, otherwise the highlighted
  // result does, otherwise the first result.
  function submit() {
    var reference = Model.parseReference(root.query)
    if (reference && service.book(reference.book)) {
      root.goTo(reference)
      root.clearQuery()
      return
    }
    if (!root.results.length) return
    root.goTo(root.cursorActive ? root.results[root.cursor] : root.results[0])
    root.clearQuery()
  }

  function clearQuery() {
    query = ""
    cursor = 0
    cursorActive = false
    searchField.text = ""
  }

  function moveCursor(delta) {
    if (!root.results.length) return
    var count = root.results.length
    if (!root.cursorActive) {
      root.cursorActive = true
      root.cursor = delta < 0 ? count - 1 : 0
      return
    }
    root.cursor = (root.cursor + delta % count + count) % count
    Qt.callLater(function() { resultList.positionViewAtIndex(root.cursor, ListView.Contain) })
  }

  function stepVerse(delta) {
    if (!service.loaded || !root.book) return
    var moved = service.step({ book: root.book, chapter: root.chapterNumber, verse: root.chapterVerse }, delta)
    if (moved) goTo(moved)
  }

  // Stepping a chapter keeps you on the same verse where the new chapter has
  // one, so paging through a chapter doesn't throw you back to its first line.
  function stepChapter(delta) {
    if (!service.loaded || !root.book) return
    goTo(service.nextChapter(root.book, root.chapterNumber, delta, root.chapterVerse))
  }

  function toggleBookmark() {
    if (!root.book || !root.chapterNumber || !root.chapterVerse) return
    var added = service.toggleBookmark(root.book, root.chapterNumber, root.chapterVerse)
    root.status = (added ? "Dodano do zakładek: " : "Usunięto z zakładek: ") + root.reference()
  }

  // One key handler for the whole panel, so the field can stay focused and every
  // letter typed goes to the query instead of being eaten as a shortcut. Reading
  // actions are therefore Ctrl-based; Tab and Escape keep their usual meaning.
  //   Enter                    open the query's top hit, else the next verse
  //   ↑ / ↓                    previous / next verse, or move through results
  //   Ctrl+N / Ctrl+P          next / previous chapter
  //   Ctrl+D                   the day's verse
  //   Ctrl+B                   toggle bookmark
  function handleKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0

    if (event.key === Qt.Key_Escape) {
      if (root.query.length > 0) root.clearQuery()
      else root.close()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      root.switchPanel(event.modifiers & Qt.ShiftModifier ? -1 : 1)
      event.accepted = true
      return
    }
    // Space is deliberately not bound: it belongs to the query, and Polish
    // references contain one ("J 3,16").
    if (!ctrl) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        // Enter reads as "go on" while a chapter is open, and as "open this" once
        // something is typed.
        if (root.query.length > 0) root.submit()
        else root.stepVerse(1)
      } else if (event.key === Qt.Key_Down) {
        if (root.query.length > 0) root.moveCursor(1)
        else root.stepVerse(1)
      } else if (event.key === Qt.Key_Up) {
        if (root.query.length > 0) root.moveCursor(-1)
        else root.stepVerse(-1)
      } else {
        return
      }
      event.accepted = true
      return
    }

    var key = event.key
    if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Down) {
      if (root.query.length > 0) root.submit()
      else root.stepVerse(1)
    } else if (key === Qt.Key_Up) {
      if (root.query.length > 0) root.moveCursor(-1)
      else root.stepVerse(-1)
    } else if (key === Qt.Key_N) {
      root.stepChapter(1)
    } else if (key === Qt.Key_P) {
      root.stepChapter(-1)
    } else if (key === Qt.Key_D) {
      root.goToDaily()
    } else if (key === Qt.Key_B) {
      root.toggleBookmark()
    } else {
      return
    }
    event.accepted = true
  }

  Component.onCompleted: if (service.loaded) root.goToDaily()

  // The text loads asynchronously, so the day's verse is picked once the service
  // reports it has parsed rather than at construction.
  Connections {
    target: service
    function onLoadedChanged() { if (service.loaded) root.goToDaily() }
  }

  // A reopened panel starts from the chapter, not from whatever was half-typed
  // last time, and takes the keyboard immediately.
  onOpenedChanged: if (opened) {
    root.clearQuery()
    searchField.forceActiveFocus()
  }

  // ── bar button ─────────────────────────────────────────────────────────────

  // A WidgetButton rather than a BarIconButton: the icon button pins itself to a
  // 27px canvas and lets the glyph spill out of it, which a label wider than an
  // icon ("Mk 10,27") then draws over its neighbours. This one sizes to the text.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.current ? root.current.label : "✝"
    active: root.opened
    horizontalMargin: 9
    tooltipText: root.current
      ? root.current.label + " · " + (root.showVerseInTooltip ? root.current.text : "Werset dnia") + "\nKliknij, aby szukać"
      : "Biblia Tysiąclecia"
    onPressed: root.toggle()
  }

  // The open-panel dot should span the label, not a fraction of the slot.
  readonly property real openPanelIndicatorWidth: button.labelWidth

  // ── panel ──────────────────────────────────────────────────────────────────

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(560))
    // A fixed height: the reading area is a ListView, which reports an implicit
    // height of zero until its delegates exist, so a measured height collapses
    // the card on open.
    contentHeight: panel.fittedContentHeight(Style.space(640), Style.space(680))

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(10)

      PanelHero {
        Layout.fillWidth: true
        title: root.book ? service.bookTitle(root.book) : "Biblia Tysiąclecia"
        meta: service.loadError !== ""
          ? service.loadError
          : (root.book
            ? root.reference() + " · " + service.translation
            : service.translation + (service.loaded ? " · " + service.verses.length + " wersetów" : " · wczytywanie…"))
        detail: root.book ? (service.isNewTestament(root.book) ? "NT" : "ST") : ""
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      TextField {
        id: searchField
        Layout.fillWidth: true
        foreground: root.foreground
        placeholderText: "J 3,16  ·  1 Kor 13,4-7  ·  szukaj: miłość  ·  @ zakładki"
        // One-way: the field owns its text and reports changes. Binding
        // `text: root.query` back as well makes the two fight, and keystrokes get
        // dropped while a query is being cleared.
        onTextChanged: {
          root.query = text
          root.cursor = 0
          root.cursorActive = false
        }
        // Keys.priority BeforeItem so the panel's reading shortcuts are seen
        // before the field's own text handling.
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { root.handleKey(event) }
      }

      PanelSectionHeader {
        Layout.fillWidth: true
        visible: root.query.length > 0
        text: root.query.charAt(0) === "@"
          ? "ZAKŁADKI · " + root.results.length
          : (root.results.length ? "WYNIKI · " + root.results.length : "BRAK WYNIKÓW")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      // Search results or the chapter, depending on what is typed. Both fill the
      // leftover height so the card keeps a stable size in either mode.
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ListView {
          id: resultList
          anchors.fill: parent
          visible: root.query.length > 0
          clip: true
          model: root.results
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          currentIndex: root.cursorActive ? root.cursor : -1
          highlightMoveDuration: 0

          // ListView takes the object form of the attached scrollbar; only
          // ScrollView supports the grouped ".policy" shorthand.
          ScrollBar.vertical: ScrollBar {
            policy: resultList.contentHeight > resultList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
          }

          delegate: Rectangle {
            required property var modelData
            required property int index
            width: ListView.view.width
            height: resultText.implicitHeight + Style.space(10)
            radius: Style.cornerRadius
            color: root.cursorActive && index === root.cursor ? Style.hoverFill : "transparent"

            Behavior on color { ColorAnimation { duration: Style.duration(120) } }

            Column {
              width: parent.width - Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: 1

              Text {
                width: parent.width
                text: Model.reference(modelData.book, modelData.chapter, modelData.verse)
                color: root.cursorActive && index === root.cursor ? Color.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                id: resultText
                width: parent.width
                text: modelData.text
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.cursorActive = true
                root.cursor = index
                root.goTo(modelData)
                root.clearQuery()
              }
            }
          }
        }

        ListView {
          id: chapterList
          anchors.fill: parent
          visible: root.query.length === 0 && !!root.book
          clip: true
          model: service.loaded && root.book ? (service.chapter(root.book, root.chapterNumber) || { verses: [] }).verses : []
          spacing: Style.space(8)
          boundsBehavior: Flickable.StopAtBounds
          currentIndex: indexOfVerse(root.chapterVerse)

          function indexOfVerse(number) {
            var list = model || []
            for (var i = 0; i < list.length; i++) {
              if (list[i].v === number) return i
            }
            return -1
          }

          ScrollBar.vertical: ScrollBar {
            policy: chapterList.contentHeight > chapterList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
          }

          delegate: Rectangle {
            id: verseRow
            required property var modelData
            width: ListView.view.width
            height: verseText.implicitHeight + Style.space(12)
            radius: Style.cornerRadius
            color: modelData.v === root.chapterVerse ? Style.hoverFill : "transparent"

            Behavior on color { ColorAnimation { duration: Style.duration(140) } }

            Row {
              width: parent.width - Style.space(8)
              spacing: Style.space(8)

              Text {
                width: Style.space(26)
                horizontalAlignment: Text.AlignRight
                text: verseRow.modelData.v
                color: verseRow.modelData.v === root.chapterVerse ? Color.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: verseRow.modelData.v === root.chapterVerse
              }

              Text {
                id: verseText
                width: parent.width - Style.space(34)
                text: verseRow.modelData.t
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.chapterVerse = verseRow.modelData.v
                root.status = ""
              }
            }
          }
        }
      }

      Text {
        Layout.fillWidth: true
        visible: root.status !== ""
        text: root.status
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
      }

      PanelSeparator {
        Layout.fillWidth: true
        foreground: root.foreground
      }

      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: root.query.length > 0
          ? "Enter otwiera wynik · ↑↓ przeglądaj wyniki · Esc wraca do rozdziału"
          : "↑↓ wersety · Ctrl+N/P rozdział · Ctrl+D werset dnia · Ctrl+B zakładka · @ lista zakładek · Tab następny panel"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }
}