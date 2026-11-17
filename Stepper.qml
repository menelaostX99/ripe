import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A number with minus and plus buttons that can also be typed into or
// scrolled over. The field is filled in by hand rather than bound to `value`:
// a binding would write the old number back over whatever is being typed.
Row {
  id: root

  property int value: 0
  property int from: 0
  property int to: 100
  property int step: 1
  property string suffix: ""
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real fieldWidth: Style.space(46)

  readonly property bool editing: input.activeFocus

  signal modified(int value)
  // Typing is over; the panel takes the keyboard back.
  signal editingDone()

  spacing: Style.spacing.sm

  // Start typing a new value.
  function edit() {
    input.forceActiveFocus()
  }

  function bump(delta) {
    var next = Math.max(from, Math.min(to, value + delta))
    if (next !== value) modified(next)
  }

  function commit() {
    var typed = parseInt(input.text, 10)
    if (isFinite(typed)) {
      typed = Math.max(from, Math.min(to, typed))
      if (typed !== value) modified(typed)
    }
    input.text = String(value)
  }

  onValueChanged: if (!input.activeFocus) input.text = String(value)
  Component.onCompleted: input.text = String(value)

  Button {
    anchors.verticalCenter: parent.verticalCenter
    iconText: ""
    iconSize: Style.font.caption
    background: Util.alpha(root.foreground, 0.06)
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    opacity: root.value > root.from ? 1 : 0.4
    onClicked: root.bump(-root.step)
  }

  BorderSurface {
    id: field
    anchors.verticalCenter: parent.verticalCenter
    width: root.fieldWidth
    height: Math.max(Style.spacing.controlHeight, root.fontSize + Style.spacing.controlPaddingY * 2)
    radius: Style.cornerRadius
    color: Style.controlFill(input.activeFocus, hover.hovered, root.foreground, root.accent)
    borderSpec: Border.controlSpec(input.activeFocus ? "focus" : (hover.hovered ? "hover-cursor" : "normal"), root.foreground, root.accent)

    HoverHandler { id: hover }

    TextInput {
      id: input
      anchors.fill: parent
      horizontalAlignment: TextInput.AlignHCenter
      verticalAlignment: TextInput.AlignVCenter
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: true
      selectByMouse: true
      maximumLength: 3
      inputMethodHints: Qt.ImhDigitsOnly
      validator: IntValidator { bottom: 0; top: 999 }
      selectionColor: Style.selectionFillFor(root.foreground, root.accent)
      selectedTextColor: root.foreground
      onActiveFocusChanged: {
        if (activeFocus) selectAll()
        else root.commit()
      }
      onAccepted: {
        root.commit()
        root.editingDone()
      }
      Keys.onEscapePressed: {
        text = String(root.value)
        root.editingDone()
      }
    }

    WheelHandler {
      property real remainder: 0
      onWheel: function(event) {
        var result = Util.wheelSteps(remainder, event.angleDelta.y)
        remainder = result.remainder
        if (result.steps !== 0) root.bump(result.steps * root.step)
      }
    }
  }

  Button {
    anchors.verticalCenter: parent.verticalCenter
    iconText: ""
    iconSize: Style.font.caption
    background: Util.alpha(root.foreground, 0.06)
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    opacity: root.value < root.to ? 1 : 0.4
    onClicked: root.bump(root.step)
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    visible: root.suffix !== ""
    leftPadding: Style.spacing.sm
    textFormat: Text.PlainText
    text: root.suffix
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
