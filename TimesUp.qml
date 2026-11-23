import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "."

// The time's-up screen: a see-through shade over everything on a monitor,
// with the message and what to do next in the middle. It takes the keyboard
// so it cannot be typed through, and goes away on Esc, a click on the shade,
// or any of its buttons.
//
// It arrives while you are in the middle of something, so for its first
// moments it answers to nothing: the keystroke or click that was already on
// its way to your work must not be the one that dismisses it.
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
  // Keys and clicks count only once this is set.
  property bool armed: false
  // How many of the screen's pieces have come in: they arrive one after
  // another, top to bottom.
  property int stage: 0
  readonly property int stages: 7

  Component.onCompleted: {
    kind = RipeStore.alert === "break" ? "break" : "focus"
    minutes = RipeStore.alertMinutes
    shown = true
    if (Style.reduceMotion) stage = stages
  }

  Timer {
    interval: 700
    running: true
    onTriggered: win.armed = true
  }

  Timer {
    interval: 60
    repeat: true
    running: win.stage < win.stages
    onTriggered: win.stage++
  }

  // One piece of the screen: it fades up into place when its turn comes.
  component Rise: Item {
    id: rise
    property int order: 0
    default property alias content: slot.data
    readonly property bool arrived: win.stage > order
    width: parent ? parent.width : 0
    implicitHeight: slot.childrenRect.height

    Item {
      id: slot
      width: parent.width
      height: childrenRect.height
      opacity: rise.arrived ? 1 : 0
      transform: Translate {
        y: rise.arrived ? 0 : Style.space(12)
        Behavior on y {
          NumberAnimation { duration: Style.duration(260); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
        }
      }
      Behavior on opacity { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
    }
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

    opacity: win.armed ? 1 : 0.55
    Behavior on opacity { NumberAnimation { duration: Style.duration(180) } }

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
      enabled: win.armed
      onClicked: choice.clicked()
    }
  }

  // The shade is a vignette: lighter in the middle, where the message is
  // and the desktop still shows through, and closing in towards the edges.
  Shape {
    id: vignette
    anchors.fill: parent
    opacity: win.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Style.duration(260); easing.type: Easing.OutCubic } }

    ShapePath {
      strokeColor: "transparent"
      strokeWidth: 0
      fillGradient: RadialGradient {
        centerX: vignette.width / 2
        centerY: vignette.height / 2
        focalX: centerX
        focalY: centerY
        centerRadius: Math.sqrt(vignette.width * vignette.width + vignette.height * vignette.height) / 2
        GradientStop { position: 0; color: Util.alpha(win.shade, 0.6) }
        GradientStop { position: 0.45; color: Util.alpha(win.shade, 0.68) }
        GradientStop { position: 1; color: Util.alpha(win.shade, 0.92) }
      }
      PathRectangle {
        width: vignette.width
        height: vignette.height
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: if (win.armed) RipeStore.dismissAlert()
    }
  }

  Item {
    anchors.fill: parent
    focus: true
    Keys.onPressed: function(event) {
      event.accepted = true
      if (!win.armed) return
      if (event.key === Qt.Key_Escape) RipeStore.dismissAlert()
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) RipeStore.acceptAlert()
      else if (event.text === "5" || event.text === "+") RipeStore.extendAlert(5)
      else if (event.text.toLowerCase() === "s" && win.afterFocus) RipeStore.declineAlert()
    }

    Column {
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(64), Style.space(720))
      spacing: Style.space(14)

      // The tomato, ripe. While a break is counting down a ring around it
      // runs out with the break, and a halo breathes slowly in and out:
      // something to breathe along with, away from the work.
      Rise {
        order: 0
        Item {
          id: emblem
          anchors.horizontalCenter: parent.horizontalCenter
          width: Style.space(132)
          height: width
          transformOrigin: Item.Center
          scale: win.stage > 0 ? 1 : 0.95
          Behavior on scale {
            NumberAnimation { duration: Style.duration(280); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
          }

          readonly property bool resting: win.afterFocus && win.nextRunning
          // 0 breathed out, 1 breathed in.
          property real breath: 0
          SequentialAnimation on breath {
            running: emblem.resting && !Style.reduceMotion
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: 1; duration: 4000; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1; to: 0; duration: 6000; easing.type: Easing.InOutSine }
          }

          Rectangle {
            anchors.centerIn: parent
            width: Style.space(104)
            height: width
            radius: width / 2
            color: Util.alpha(win.accent, 0.10 + 0.08 * emblem.breath)
            scale: 0.92 + 0.26 * emblem.breath
            opacity: emblem.resting ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Style.duration(240) } }
          }
          Ring {
            anchors.fill: parent
            lineWidth: Style.space(3)
            remaining: 1 - RipeStore.progress
            color: win.accent
            trackColor: Util.alpha(win.fg, 0.12)
            opacity: emblem.resting ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Style.duration(240) } }
            Behavior on remaining { NumberAnimation { duration: Style.duration(1000) } }
          }
          Tomato {
            anchors.centerIn: parent
            width: Style.space(72)
            height: width
            color: win.accent
          }
        }
        // Room between the ring and the words under it.
        Item { y: emblem.height; width: 1; height: Style.space(10) }
      }

      Rise {
        order: 1
        Words {
          width: parent.width
          text: win.afterFocus ? strings.t("alert.focus.eyebrow") : strings.t("alert.break.eyebrow")
          color: win.accent
          font.pixelSize: Style.font.subtitle
          font.bold: true
          font.letterSpacing: 3
        }
      }
      Rise {
        order: 2
        Words {
          width: parent.width
          text: win.afterFocus ? strings.t("alert.focus.title") : strings.t("alert.break.title")
          font.pixelSize: Style.space(72)
          font.weight: Font.Light
          fontSizeMode: Text.HorizontalFit
          minimumPixelSize: Style.space(32)
        }
      }
      Rise {
        order: 3
        Words {
          width: parent.width
          wrapMode: Text.WordWrap
          color: win.dim
          font.pixelSize: Style.font.heading
          lineHeight: 1.35
          text: (win.afterFocus ? strings.tn("alert.focus.done", win.minutes) : strings.tn("alert.break.done", win.minutes))
            .arg(win.number(win.minutes))
        }
      }

      // What happens next: a break already counting down, or one on offer.
      Rise {
        order: 4
        Words {
          width: parent.width
          topPadding: Style.space(4)
          bottomPadding: Style.space(10)
          font.pixelSize: Style.font.display
          text: win.nextRunning
            ? (win.afterFocus ? strings.t("alert.focus.running") : strings.t("alert.break.running")).arg(RipeStore.clockText)
            : (win.afterFocus ? strings.t("alert.focus.body") : strings.t("alert.break.body")).arg(win.number(win.nextMinutes))
        }
      }

      Rise {
        order: 5
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
      }

      Rise {
        order: 6
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
}
