import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "."

// The time's-up screen: a see-through shade over everything on a monitor,
// with the message and what to do next in the middle. It takes the keyboard
// so it cannot be typed through, and goes away on Esc, a click on the shade,
// or any of its buttons.
PanelWindow {
  id: win

  required property var modelData
  screen: modelData

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"

  WlrLayershell.namespace: "ripe-timesup"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  // Held from when the window was made: the alert is cleared a moment before
  // the window goes, and the text should not change on the way out.
  property string kind: "focus"
  property int minutes: 0
  readonly property bool afterFocus: kind === "focus"
  readonly property bool nextRunning: RipeStore.running
  readonly property int nextMinutes: Number(RipeStore.settings[afterFocus ? "break" : "focus"])

  readonly property color fg: Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color accent: Commons.Color.accent
  readonly property color shade: Commons.Color.background
  readonly property string fontFamily: Style.font.family

  property bool shown: false
  Component.onCompleted: {
    kind = RipeStore.alert === "break" ? "break" : "focus"
    minutes = RipeStore.alertMinutes
    shown = true
  }

  function number(value) {
    return Commons.I18n.formatNumber(value, 0)
  }

  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  component Words: Text {
    textFormat: Text.PlainText
    color: win.fg
    font.family: win.fontFamily
    horizontalAlignment: Text.AlignHCenter
  }

  component Choice: Rectangle {
    id: choice
    property string text: ""
    property bool primary: false
    signal clicked()

    implicitWidth: choiceLabel.implicitWidth + Style.space(44)
    implicitHeight: Style.space(42)
    radius: Style.cornerRadius
    color: primary
      ? (choiceMouse.pressed ? Qt.darker(win.accent, 1.15) : choiceMouse.containsMouse ? Qt.lighter(win.accent, 1.1) : win.accent)
      : Util.alpha(win.fg, choiceMouse.pressed ? 0.2 : choiceMouse.containsMouse ? 0.14 : 0.07)
    border.width: primary ? 0 : 1
    border.color: Util.alpha(win.fg, 0.22)
    scale: choiceMouse.pressed ? 0.97 : 1
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    Behavior on scale {
      NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    Words {
      id: choiceLabel
      anchors.centerIn: parent
      text: choice.text
      color: choice.primary ? win.shade : win.fg
      font.pixelSize: Style.font.title
      font.bold: choice.primary
    }
    MouseArea {
      id: choiceMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: choice.clicked()
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(win.shade, 0.66)
    opacity: win.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }

    MouseArea {
      anchors.fill: parent
      onClicked: RipeStore.dismissAlert()
    }
  }

  Item {
    anchors.fill: parent
    focus: true
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) RipeStore.dismissAlert()
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) RipeStore.acceptAlert()
      else if (event.text === "5" || event.text === "+") RipeStore.extendAlert(5)
      else if (event.text.toLowerCase() === "s" && win.afterFocus) RipeStore.declineAlert()
      event.accepted = true
    }

    Column {
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(64), Style.space(720))
      spacing: Style.space(14)
      opacity: win.shown ? 1 : 0
      scale: win.shown ? 1 : 0.97
      Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
      Behavior on scale {
        NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
      }

      Tomato {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Style.space(72)
        height: width
        color: win.accent
      }

      Item { width: 1; height: Style.space(6) }

      Words {
        width: parent.width
        text: win.afterFocus ? strings.t("alert.focus.eyebrow") : strings.t("alert.break.eyebrow")
        color: win.accent
        font.pixelSize: Style.font.subtitle
        font.bold: true
        font.letterSpacing: 3
      }
      Words {
        width: parent.width
        text: win.afterFocus ? strings.t("alert.focus.title") : strings.t("alert.break.title")
        font.pixelSize: Style.space(72)
        font.weight: Font.Light
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: Style.space(32)
      }
      Words {
        width: parent.width
        wrapMode: Text.WordWrap
        color: win.dim
        font.pixelSize: Style.font.heading
        lineHeight: 1.35
        text: (win.afterFocus ? strings.tn("alert.focus.done", win.minutes) : strings.tn("alert.break.done", win.minutes))
          .arg(win.number(win.minutes))
      }

      Item { width: 1; height: Style.space(4) }

      // What happens next: a break already counting down, or one on offer.
      Words {
        width: parent.width
        font.pixelSize: Style.font.display
        text: win.nextRunning
          ? (win.afterFocus ? strings.t("alert.focus.running") : strings.t("alert.break.running")).arg(RipeStore.clockText)
          : (win.afterFocus ? strings.t("alert.focus.body") : strings.t("alert.break.body")).arg(win.number(win.nextMinutes))
      }

      Item { width: 1; height: Style.space(10) }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(12)

        Choice {
          primary: true
          text: win.nextRunning ? strings.t("alert.ok")
            : win.afterFocus ? strings.t("alert.focus.accept") : strings.t("alert.break.accept")
          onClicked: RipeStore.acceptAlert()
        }
        Choice {
          text: strings.t("alert.extend")
          onClicked: RipeStore.extendAlert(5)
        }
        Choice {
          visible: win.afterFocus
          text: strings.t("alert.focus.decline")
          onClicked: RipeStore.declineAlert()
        }
      }

      Words {
        width: parent.width
        topPadding: Style.space(8)
        color: Util.alpha(win.fg, 0.45)
        font.pixelSize: Style.font.bodySmall
        text: win.afterFocus ? strings.t("alert.focus.keys") : strings.t("alert.break.keys")
      }
    }
  }
}
