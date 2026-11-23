import QtQuick
import qs.Commons
import "Model.js" as Model

// A clock set digit by digit. Every digit sits in a cell as wide as the
// font's widest one, so the clock does not shuffle sideways as it counts in
// a proportional font, and a digit that changes rolls over while the others
// stay put.
Row {
  id: root

  property string text: ""
  property color color: "white"
  property string fontFamily: Style.font.family
  property int pixelSize: Style.font.body
  property int weight: Font.Normal

  readonly property var cells: Model.clockCells(text)
  readonly property real digitWidth: {
    // Named so the width is measured again when the font changes.
    var family = metrics.font.family, size = metrics.font.pixelSize, weight = metrics.font.weight
    var widest = 0
    for (var d = 0; d < 10; d++) widest = Math.max(widest, metrics.advanceWidth(String(d)))
    return Math.ceil(widest)
  }

  FontMetrics {
    id: metrics
    font.family: root.fontFamily
    font.pixelSize: root.pixelSize
    font.weight: root.weight
  }

  component Glyph: Text {
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    textFormat: Text.PlainText
    color: root.color
    font: metrics.font
  }

  Repeater {
    model: root.cells.length

    Item {
      id: cell
      required property int index
      readonly property string ch: root.cells[index] || ""
      readonly property bool digit: ch >= "0" && ch <= "9"
      property string shown: ch
      property string leaving: ""
      // 0 as a new digit starts to roll in, 1 once it has settled.
      property real settle: 1

      width: digit ? root.digitWidth : Math.ceil(metrics.advanceWidth(ch))
      height: Math.ceil(metrics.height)

      onChChanged: {
        if (ch === shown) return
        leaving = shown
        shown = ch
        if (digit && !Style.reduceMotion) roll.restart()
        else settle = 1
      }

      NumberAnimation {
        id: roll
        target: cell
        property: "settle"
        from: 0
        to: 1
        duration: Style.duration(220)
        easing.type: Easing.OutCubic
      }

      // The clock counts down, so digits fall: the old one drops away as
      // the new one comes down into its place.
      Glyph {
        visible: cell.settle < 1
        text: cell.leaving
        y: cell.settle * cell.height * 0.4
        opacity: 1 - cell.settle
      }
      Glyph {
        text: cell.shown
        y: (cell.settle - 1) * cell.height * 0.4
        opacity: cell.settle
      }
    }
  }
}
