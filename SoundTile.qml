import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons

// One sound in the mix. A click adds or removes it; dragging across the tile
// or scrolling over it sets how loud it is, and the tile fills to that level.
Item {
  id: root

  property string label: ""
  property url icon: ""
  property bool active: false
  // Playing right now, as opposed to merely picked for the next session.
  property bool sounding: false
  property real level: 0.6
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  signal toggled()
  signal levelPicked(real level)

  readonly property color ink: active ? foreground : Qt.darker(foreground, 1.35)

  implicitHeight: Style.space(56)

  Rectangle {
    id: plate
    anchors.fill: parent
    radius: Style.cornerRadius
    clip: true
    color: Util.alpha(root.active ? root.accent : root.foreground,
      mouse.pressed ? 0.2 : mouse.containsMouse ? (root.active ? 0.16 : 0.1) : (root.active ? 0.1 : 0.05))
    border.width: 1
    border.color: Util.alpha(root.accent, root.active ? 0.55 : 0)
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

    // The level: the tile fills from the reading edge like a meter.
    Rectangle {
      visible: root.active
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.margins: 1
      width: (parent.width - 2) * Math.max(0, Math.min(1, root.level))
      radius: Math.max(0, plate.radius - 1)
      color: Util.alpha(root.accent, root.sounding ? 0.3 : 0.14)
      Behavior on width {
        enabled: !mouse.dragging
        NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
      }
      Behavior on color { ColorAnimation { duration: Style.duration(200) } }
    }

    // Lit while this sound is actually coming out of the speakers.
    Rectangle {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(6)
      width: Style.space(5)
      height: width
      radius: width / 2
      color: root.accent
      opacity: root.sounding ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Style.duration(200) } }
    }
  }

  Column {
    anchors.centerIn: parent
    width: parent.width - Style.space(8)
    spacing: Style.space(4)

    Image {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Style.space(20)
      height: width
      sourceSize: Qt.size(width * 2, height * 2)
      source: root.icon
      // Blanket's icons are dark symbolic glyphs: push them to white, then
      // tint, so they follow the theme.
      layer.enabled: true
      layer.effect: MultiEffect {
        brightness: 1.0
        colorization: 1.0
        colorizationColor: root.ink
      }
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: root.label
      elide: Text.ElideRight
      color: root.ink
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    preventStealing: true
    cursorShape: Qt.PointingHandCursor

    property bool dragging: false
    property real pressX: 0
    property real wheelRemainder: 0

    function levelAt(x) {
      var fraction = Math.max(0.05, Math.min(1, x / width))
      return LayoutMirroring.enabled ? Math.max(0.05, 1.05 - fraction) : fraction
    }

    onPressed: function(event) {
      pressX = event.x
      dragging = false
    }
    onPositionChanged: function(event) {
      if (!pressed) return
      if (!dragging && Math.abs(event.x - pressX) > Style.space(5)) dragging = true
      if (dragging) root.levelPicked(levelAt(event.x))
    }
    onReleased: {
      if (!dragging) root.toggled()
      dragging = false
    }
    onCanceled: dragging = false
    onWheel: function(event) {
      var result = Util.wheelSteps(wheelRemainder, event.angleDelta.y)
      wheelRemainder = result.remainder
      if (result.steps !== 0)
        root.levelPicked(Math.max(0.05, Math.min(1, root.level + result.steps * 0.05)))
    }
  }
}
