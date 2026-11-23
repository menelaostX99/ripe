import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "."
import "Model.js" as Model

// The bar button and the popup it opens. All of the timer's state lives in
// RipeStore.qml; this file only shows it and passes on what the user asks for.
Panel {
  id: root
  moduleName: "menelaostx99.ripe"
  ipcTarget: "menelaostx99.ripe"

  readonly property var svc: RipeStore
  readonly property var cfg: svc.settings
  readonly property string phase: svc.phase
  readonly property bool running: svc.running
  readonly property bool paused: svc.paused
  readonly property bool idle: !running && !paused
  readonly property real remaining: 1 - svc.progress
  readonly property string clockText: svc.clockText

  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color faint: Util.alpha(fg, 0.45)
  readonly property color accent: Commons.Color.accent
  // Text that sits on an accent fill.
  readonly property color onAccent: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 1)
  // Focus wears the accent; a break is deliberately quieter.
  readonly property color phaseColor: phase === "focus" ? accent : fg
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var locale: Qt.locale(Commons.I18n.formatLocale)
  readonly property bool vertical: bar ? bar.vertical : false

  property bool showOptions: false
  // Typing a name for the mix that is playing.
  property bool namingMix: false
  onOpenedChanged: if (!opened) {
    showOptions = false
    namingMix = false
  }

  // A colour part of the way from one to another.
  function blend(from, to, amount) {
    var t = Math.max(0, Math.min(1, amount))
    return Qt.rgba(from.r + (to.r - from.r) * t, from.g + (to.g - from.g) * t, from.b + (to.b - from.b) * t, 1)
  }

  function number(value) {
    return Commons.I18n.formatNumber(value, 0)
  }

  readonly property string stateLabel: {
    if (paused) return strings.t("state.paused")
    if (running) return strings.t("state." + phase)
    return strings.t("state.ready")
  }

  readonly property string detailLabel: {
    if (running) return strings.t("ends").arg(new Date(svc.endsAt).toLocaleTimeString(locale, Locale.ShortFormat))
    return strings.t("length").arg(number(svc.sessionMinutes))
  }

  function nudge(minutes) {
    svc.nudge(minutes)
  }

  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---------------------------------------------------------------- bar

  TextMetrics {
    id: barClock
    font.family: root.fontFamily
    font.pixelSize: Style.bar.iconFont
    // Measured with every digit a zero, so the slot keeps one width for the
    // whole session instead of following each second's digits.
    text: Model.clockTemplate(root.clockText)
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar

    readonly property bool showClock: !root.idle && !root.vertical
    slotSize: Style.bar.statusSlot + (showClock ? Math.ceil(barClock.advanceWidth) + Style.space(12) : 0)
    labelText: showClock ? root.clockText : ""
    // Paused, the button rests dim and slowly comes up for air, so a clock
    // that has stopped is not mistaken for one that is running.
    property bool surfaced: false
    dimmed: root.paused && !surfaced
    Behavior on opacity { NumberAnimation { duration: Style.duration(700); easing.type: Easing.OutCubic } }
    Timer {
      interval: 1400
      repeat: true
      running: root.paused && !Style.reduceMotion
      onRunningChanged: button.surfaced = false
      onTriggered: button.surfaced = !button.surfaced
    }
    tooltipText: root.opened ? "" : strings.t("tooltip")
    // Ripe at rest. A session starts it empty and it ripens as the work
    // gets done, so the bar shows how far along you are at a glance.
    iconComponent: Component {
      Tomato {
        id: mark
        width: 16
        height: 16
        color: button.foreground
        level: root.idle ? 1 : root.svc.progress

        // The last minute: a slow pulse says the end is near.
        readonly property bool closing: root.running && root.svc.remainingMs <= 60000 && !Style.reduceMotion
        SequentialAnimation on opacity {
          running: mark.closing
          loops: Animation.Infinite
          alwaysRunToEnd: true
          NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
        }

        // A phase ran out: the tomato swells once.
        NumberAnimation {
          id: swell
          target: mark
          property: "scale"
          from: 1.18
          to: 1
          duration: Style.duration(320)
          easing.type: Easing.OutCubic
        }
        Connections {
          target: root.svc
          function onFinished() { swell.restart() }
        }
      }
    }
    onPressed: function(b) {
      if (b === Qt.RightButton) root.svc.toggle()
      else if (b === Qt.MiddleButton) root.svc.skip()
      else root.toggle()
    }
  }

  // -------------------------------------------------------------- popup

  component Label: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  // A quiet square button that is only an icon.
  component IconButton: Button {
    width: Style.space(36)
    height: Style.space(36)
    horizontalPadding: 0
    verticalPadding: 0
    iconSize: Style.font.title
    foreground: root.fg
    accent: root.accent
    fontFamily: root.fontFamily
    background: Util.alpha(root.fg, 0.06)
  }

  component OptionRow: Item {
    id: optionRow
    property alias text: optionLabel.text
    property bool checked: false
    signal toggled()
    width: parent ? parent.width : 0
    implicitHeight: Style.space(38)

    Label {
      id: optionLabel
      anchors.left: parent.left
      anchors.right: optionSwitch.left
      anchors.rightMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
    }
    ToggleSwitch {
      id: optionSwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      foreground: root.fg
      accent: root.accent
      cursorRing: false
      checked: optionRow.checked
      onToggled: optionRow.toggled()
    }
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: Util.alpha(root.fg, 0.07)
    }
  }

  // A saved mix: click to load it, right-click to forget it. The name is
  // the user's own text, so it is only ever drawn as plain text.
  component MixChip: Rectangle {
    id: chip
    property string name: ""
    property bool current: false
    signal picked()
    signal removed()

    implicitWidth: Math.min(chipLabel.implicitWidth, Style.space(140)) + Style.space(18)
    implicitHeight: Style.space(26)
    radius: Style.cornerRadius
    color: Util.alpha(current ? root.accent : root.fg, chipMouse.pressed ? 0.22 : chipMouse.containsMouse ? 0.16 : (current ? 0.12 : 0.06))
    border.width: 1
    border.color: Util.alpha(root.accent, current ? 0.55 : 0)
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

    Label {
      id: chipLabel
      anchors.centerIn: parent
      width: Math.min(implicitWidth, Style.space(140))
      elide: Text.ElideRight
      text: chip.name
      color: chip.current ? root.fg : root.dim
      font.pixelSize: Style.font.bodySmall
    }
    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(event) {
        if (event.button === Qt.RightButton) chip.removed()
        else chip.picked()
      }
    }
  }

  // A key and what it does, drawn as a keycap beside a word.
  component KeyHint: Row {
    id: hint
    property string key: ""
    property string label: ""
    spacing: Style.space(5)

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(height, capLabel.implicitWidth + Style.space(10))
      height: Style.space(18)
      radius: Math.min(4, Style.cornerRadius)
      color: Util.alpha(root.fg, 0.07)
      border.width: 1
      border.color: Util.alpha(root.fg, 0.16)

      Label {
        id: capLabel
        anchors.centerIn: parent
        text: hint.key
        color: Util.alpha(root.fg, 0.75)
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
    Label {
      anchors.verticalCenter: parent.verticalCenter
      text: hint.label
      color: Util.alpha(root.fg, 0.45)
      font.pixelSize: Style.font.caption
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    padding: Style.space(20)
    contentWidth: panel.fittedContentWidth(timerColumn.width + mixColumn.width + columns.spacing * 2 + 1
      + panel.padding * 2 + Border.left(panel.borderSpec) + Border.right(panel.borderSpec))
    contentHeight: panel.fittedContentHeight(layout.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      blocked: minutesStepper.editing || root.namingMix

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: root.svc.toggle()
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.nudge(dx)
        else root.nudge(-dy * 5)
      }
      onTextKey: function(key) {
        var k = key.toLowerCase()
        if (k === "s") root.svc.skip()
        else if (k === "r") root.svc.reset()
        else if (k === "m") root.svc.toggleAmbient()
        else if (k === "n") root.svc.nextMix()
        else if (k === "o") root.showOptions = !root.showOptions
        else if (k === "e") minutesStepper.edit()
        else if (k === "1") root.svc.selectPhase("focus")
        else if (k === "2") root.svc.selectPhase("break")
        else if (k === "+" || k === "=") root.nudge(1)
        else if (k === "-") root.nudge(-1)
      }

      Column {
        id: layout
        spacing: Style.space(16)

        Row {
          id: columns
          spacing: Style.space(22)

          // -------------------------------------------------- timer
          Column {
            id: timerColumn
            width: Style.space(250)
            spacing: Style.space(16)

            // Focus or break: two halves with a thumb that slides between them.
            Rectangle {
              id: tabs
              width: parent.width
              height: Style.space(32)
              radius: Style.cornerRadius
              color: Util.alpha(root.fg, 0.06)

              readonly property real inset: Style.space(3)
              readonly property real half: (width - inset * 2) / 2

              Rectangle {
                y: tabs.inset
                width: tabs.half
                height: tabs.height - tabs.inset * 2
                radius: Math.max(0, tabs.radius - tabs.inset)
                color: Util.alpha(root.fg, 0.14)
                x: tabs.inset + ((root.phase === "break") !== LayoutMirroring.enabled ? tabs.half : 0)
                Behavior on x {
                  NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
                }
              }

              Row {
                anchors.fill: parent
                anchors.margins: tabs.inset
                Repeater {
                  model: Model.PHASES
                  Item {
                    id: tab
                    required property string modelData
                    readonly property bool current: root.phase === modelData
                    width: tabs.half
                    height: parent.height

                    Label {
                      anchors.centerIn: parent
                      text: strings.t("phase." + tab.modelData)
                      color: tab.current ? root.fg : root.dim
                      font.bold: tab.current
                      Behavior on color { ColorAnimation { duration: Style.duration(160) } }
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.svc.selectPhase(tab.modelData)
                    }
                  }
                }
              }
            }

            // The dial: a ring that empties clockwise, a minute track inside
            // it, and the time in the middle. Clicking it starts or pauses.
            Item {
              id: dial
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(212)
              height: width
              scale: dialMouse.pressed ? 0.98 : 1
              Behavior on scale {
                NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
              }

              readonly property real stroke: Style.space(5)
              readonly property real orbit: (width - stroke) / 2 - Style.space(4)

              // Starting a session winds the dial up like a kitchen timer:
              // the ring and its minute marks sweep round to full, then the
              // clock takes over. 1 whenever nothing is being wound.
              property real wind: 1
              property bool winding: false
              SequentialAnimation {
                id: windUp
                PropertyAction { target: dial; property: "winding"; value: true }
                NumberAnimation {
                  target: dial; property: "wind"; from: 0; to: 1
                  duration: Style.duration(520); easing.type: Easing.OutCubic
                }
                PropertyAction { target: dial; property: "winding"; value: false }
              }
              Connections {
                target: root.svc
                function onStarted() {
                  if (root.opened && !Style.reduceMotion) windUp.restart()
                }
                function onFinished() {
                  if (root.opened && !Style.reduceMotion) flourish.restart()
                }
              }

              // A phase ran out with the panel open: one ring of light
              // leaves the dial.
              Rectangle {
                id: ripple
                anchors.centerIn: parent
                width: ring.width
                height: width
                radius: width / 2
                color: "transparent"
                border.width: Math.max(1, Style.space(2))
                border.color: root.accent
                opacity: 0
                ParallelAnimation {
                  id: flourish
                  NumberAnimation { target: ripple; property: "scale"; from: 1; to: 1.16; duration: 600; easing.type: Easing.OutCubic }
                  NumberAnimation { target: ripple; property: "opacity"; from: 0.7; to: 0; duration: 600; easing.type: Easing.OutCubic }
                }
              }

              Repeater {
                model: 60
                Rectangle {
                  required property int index
                  readonly property bool major: index % 5 === 0
                  // Minutes still to run stay lit; spent ones go dark.
                  readonly property bool live: (root.idle || index / 60 >= 1 - root.remaining - 0.0001)
                    && index / 60 >= 1 - dial.wind - 0.0001
                  width: Math.max(1, Style.space(major ? 2 : 1))
                  height: Style.space(major ? 7 : 4)
                  radius: width / 2
                  x: dial.width / 2 - width / 2
                  y: Style.space(18)
                  color: Util.alpha(root.fg, live ? (major ? 0.5 : 0.26) : 0.08)
                  transform: Rotation {
                    origin.x: width / 2
                    origin.y: dial.height / 2 - y
                    angle: index * 6
                  }
                  Behavior on color { ColorAnimation { duration: Style.duration(200) } }
                }
              }

              Ring {
                id: ring
                anchors.fill: parent
                anchors.margins: Style.space(4)
                lineWidth: dial.stroke
                remaining: dial.winding ? dial.wind : root.remaining
                color: Util.alpha(root.phaseColor, root.paused ? 0.5 : 1)
                trackColor: Util.alpha(root.fg, 0.09)
                // The clock moves once a second; the ring glides between
                // those steps at a constant pace, and settles quickly after
                // a jump such as a new length.
                Behavior on remaining {
                  enabled: !dial.winding
                  NumberAnimation { duration: Style.duration(root.running ? 1000 : 250) }
                }
                Behavior on color { ColorAnimation { duration: Style.duration(200) } }
              }

              // A comet's tail behind the head of the ring: dots that shrink
              // and fade along the path it has just travelled.
              Repeater {
                model: 14
                Rectangle {
                  required property int index
                  readonly property real angle: head.angle - (index + 1) * 0.034
                  width: dial.stroke * (1 - index / 20)
                  height: width
                  radius: width / 2
                  x: dial.width / 2 + dial.orbit * Math.sin(angle) - width / 2
                  y: dial.height / 2 - dial.orbit * Math.cos(angle) - height / 2
                  color: Util.alpha(root.phaseColor, 0.6 * (1 - index / 14))
                  // Never drawn back past the top, where the session began.
                  visible: angle > 0
                  opacity: root.running && !dial.winding ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: Style.duration(240) } }
                }
              }

              // The head of the ring, with a soft halo, while the clock runs.
              Item {
                id: head
                readonly property real angle: 2 * Math.PI * (1 - Math.max(0, Math.min(1, ring.remaining)))
                x: dial.width / 2 + dial.orbit * Math.sin(angle)
                y: dial.height / 2 - dial.orbit * Math.cos(angle)
                opacity: root.idle ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Style.duration(180) } }

                Rectangle {
                  anchors.centerIn: parent
                  width: Style.space(22)
                  height: width
                  radius: width / 2
                  color: Util.alpha(root.phaseColor, 0.22)
                }
                Rectangle {
                  anchors.centerIn: parent
                  width: Style.space(11)
                  height: width
                  radius: width / 2
                  color: root.phaseColor
                }
              }

              Column {
                anchors.centerIn: parent
                spacing: Style.space(3)

                // The tomato ripens with the session: it fills from the
                // bottom and its colour deepens from pale to the full accent.
                Tomato {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: Style.space(22)
                  height: width
                  level: root.idle ? 1 : root.svc.progress
                  color: root.idle ? root.dim : root.blend(root.dim, root.phaseColor, 0.25 + 0.75 * root.svc.progress)
                  opacity: root.paused ? 0.55 : 1
                  Behavior on opacity { NumberAnimation { duration: Style.duration(160) } }
                }
                Item { width: 1; height: Style.space(2) }
                Label {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.stateLabel.toUpperCase()
                  color: root.running ? root.phaseColor : root.dim
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 2
                  Behavior on color { ColorAnimation { duration: Style.duration(200) } }
                }
                Digits {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.clockText
                  color: root.fg
                  fontFamily: root.fontFamily
                  pixelSize: Style.space(root.clockText.length > 5 ? 32 : 42)
                  weight: Font.Light
                  opacity: root.paused ? 0.55 : 1
                  Behavior on opacity { NumberAnimation { duration: Style.duration(160) } }
                }
                Label {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.detailLabel
                  color: root.dim
                  font.pixelSize: Style.font.bodySmall
                }
              }

              MouseArea {
                id: dialMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.svc.toggle()
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              // The one loud thing in the panel.
              Rectangle {
                id: cta
                width: parent.width - skipButton.width - resetButton.width - parent.spacing * 2
                height: Style.space(36)
                radius: Style.cornerRadius
                color: ctaMouse.pressed ? Qt.darker(root.accent, 1.15)
                  : ctaMouse.containsMouse ? Qt.lighter(root.accent, 1.1) : root.accent
                scale: ctaMouse.pressed ? 0.97 : 1
                Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                Behavior on scale {
                  NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
                }

                Row {
                  anchors.centerIn: parent
                  spacing: Style.space(9)
                  Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.running ? "" : ""
                    color: root.onAccent
                    font.pixelSize: Style.font.bodySmall
                  }
                  Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.running ? strings.t("action.pause") : root.paused ? strings.t("action.resume") : strings.t("action.start")
                    color: root.onAccent
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                  }
                }
                MouseArea {
                  id: ctaMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.svc.toggle()
                }
              }
              IconButton {
                id: skipButton
                iconText: ""
                tooltipText: strings.t("action.skip." + root.phase)
                onClicked: root.svc.skip()
              }
              IconButton {
                id: resetButton
                iconText: ""
                tooltipText: strings.t("action.reset")
                opacity: root.idle ? 0.4 : 1
                onClicked: root.svc.reset()
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(8)

              Stepper {
                id: minutesStepper
                anchors.horizontalCenter: parent.horizontalCenter
                value: root.svc.sessionMinutes
                from: Model.LIMITS[root.phase][0]
                to: Model.LIMITS[root.phase][1]
                suffix: strings.t("unit.min")
                foreground: root.fg
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(value) { root.svc.setLength(value) }
                onEditingDone: keys.forceActiveFocus()
              }

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(2)
                Repeater {
                  model: Model.PRESETS[root.phase]
                  Button {
                    required property int modelData
                    text: root.number(modelData)
                    selected: root.svc.sessionMinutes === modelData
                    horizontalPadding: Style.space(9)
                    foreground: selected ? root.fg : root.dim
                    accent: root.accent
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    onClicked: root.svc.setLength(modelData)
                  }
                }
              }
            }
          }

          Rectangle {
            width: 1
            height: Math.max(timerColumn.height, mixColumn.height)
            color: Util.alpha(root.fg, 0.08)
          }

          // --------------------------------------------- soundscape
          Column {
            id: mixColumn
            width: Style.space(352)
            spacing: Style.space(12)

            Item {
              width: parent.width
              implicitHeight: Style.space(32)

              Label {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.showOptions ? strings.t("options.title") : strings.t("sounds.title")
                color: root.dim
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 2
              }
              Button {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: root.showOptions ? "" : ""
                tooltipText: root.showOptions ? strings.t("options.close") : strings.t("options.open")
                selected: root.showOptions
                foreground: root.fg
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.showOptions = !root.showOptions
              }
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(mixView.implicitHeight, optionsView.implicitHeight)

              // ----------------------------------------- the mix
              Column {
                id: mixView
                width: parent.width
                spacing: Style.space(12)
                // The mix and the options trade places with a short slide
                // and fade instead of a cut.
                opacity: root.showOptions ? 0 : 1
                visible: opacity > 0
                enabled: !root.showOptions
                transform: Translate {
                  x: root.showOptions ? -Style.space(14) : 0
                  Behavior on x {
                    NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
                  }
                }
                Behavior on opacity { NumberAnimation { duration: Style.duration(root.showOptions ? 120 : 180); easing.type: Easing.OutCubic } }

                Row {
                  width: parent.width
                  spacing: Style.space(10)
                  visible: root.svc.soundsState !== "missing"

                  IconButton {
                    id: playButton
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: root.svc.audible ? "" : ""
                    tooltipText: root.svc.audible ? strings.t("sounds.stop") : strings.t("sounds.play")
                    selected: root.svc.audible
                    onClicked: root.svc.toggleAmbient()
                  }
                  PanelSlider {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - playButton.width - masterLabel.width - parent.spacing * 2
                    bar: root.bar
                    value: root.cfg.master
                    fillColor: root.accent
                    onMoved: function(value) { root.svc.update({ master: value }) }
                  }
                  Label {
                    id: masterLabel
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(34)
                    horizontalAlignment: Text.AlignRight
                    text: strings.t("percent").arg(root.number(Math.round(root.cfg.master * 100)))
                    color: root.dim
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                Grid {
                  id: tiles
                  width: parent.width
                  columns: 4
                  spacing: Style.space(6)
                  visible: root.svc.soundsAvailable

                  Repeater {
                    model: Model.SOUNDS
                    SoundTile {
                      required property string modelData
                      required property int index
                      width: (tiles.width - tiles.spacing * (tiles.columns - 1)) / tiles.columns
                      label: strings.t("sound." + modelData)
                      icon: "file://" + root.svc.cacheDir + "/icons/" + modelData + ".svg"
                      active: root.cfg.active.indexOf(modelData) >= 0
                      sounding: active && root.svc.audible
                      // Each tile breathes at its own pace.
                      tempo: 3200 + (index * 470) % 1900
                      level: root.cfg.levels[modelData] === undefined ? 0.6 : root.cfg.levels[modelData]
                      foreground: root.fg
                      accent: root.accent
                      fontFamily: root.fontFamily
                      onToggled: root.svc.toggleSound(modelData)
                      onLevelPicked: function(level) { root.svc.setSoundLevel(modelData, level) }
                    }
                  }
                }

                // Saved mixes, and a way to save the one that is picked now.
                Flow {
                  id: mixes
                  width: parent.width
                  spacing: Style.space(6)
                  visible: root.svc.soundsAvailable && (root.cfg.mixes.length > 0 || canSave)

                  readonly property bool canSave: root.cfg.active.length > 0 && root.svc.currentMix < 0
                    && root.cfg.mixes.length < Model.MAX_MIXES

                  Repeater {
                    model: root.cfg.mixes
                    MixChip {
                      required property var modelData
                      required property int index
                      name: modelData.name
                      current: index === root.svc.currentMix
                      onPicked: root.svc.loadMix(modelData.name)
                      onRemoved: root.svc.deleteMix(modelData.name)
                    }
                  }

                  MixChip {
                    visible: mixes.canSave && !root.namingMix
                    name: strings.t("mix.save")
                    onPicked: {
                      root.namingMix = true
                      mixName.text = ""
                      mixName.forceActiveFocus()
                    }
                  }

                  BorderSurface {
                    visible: root.namingMix
                    width: Style.space(170)
                    height: Style.space(26)
                    radius: Style.cornerRadius
                    color: Style.controlFill(true, false, root.fg, root.accent)
                    borderSpec: Border.controlSpec("focus", root.fg, root.accent)

                    Label {
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(8)
                      verticalAlignment: Text.AlignVCenter
                      visible: mixName.text === ""
                      text: strings.t("mix.name")
                      color: root.faint
                      font.pixelSize: Style.font.bodySmall
                    }
                    TextInput {
                      id: mixName
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(8)
                      anchors.rightMargin: Style.space(8)
                      verticalAlignment: TextInput.AlignVCenter
                      clip: true
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      maximumLength: Model.MAX_MIX_NAME
                      selectionColor: Style.selectionFillFor(root.fg, root.accent)
                      selectedTextColor: root.fg
                      function done() {
                        root.namingMix = false
                        keys.forceActiveFocus()
                      }
                      onAccepted: {
                        root.svc.saveMix(text)
                        done()
                      }
                      Keys.onEscapePressed: done()
                      onActiveFocusChanged: if (!activeFocus) root.namingMix = false
                    }
                  }
                }

                Label {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  color: root.faint
                  font.pixelSize: Style.font.caption
                  lineHeight: 1.3
                  text: root.svc.soundsState === "missing" ? strings.t("sounds.missing")
                    : root.svc.soundsState === "checking" ? strings.t("sounds.checking")
                    : root.svc.soundError !== "" ? strings.t("sounds.error").arg(strings.t("sound." + root.svc.soundError))
                    : strings.t("sounds.hint")
                }
              }

              // ------------------------------------- the options
              Column {
                id: optionsView
                width: parent.width
                opacity: root.showOptions ? 1 : 0
                visible: opacity > 0
                enabled: root.showOptions
                transform: Translate {
                  x: root.showOptions ? 0 : Style.space(14)
                  Behavior on x {
                    NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
                  }
                }
                Behavior on opacity { NumberAnimation { duration: Style.duration(root.showOptions ? 180 : 120); easing.type: Easing.OutCubic } }

                Repeater {
                  model: Model.FLAGS
                  OptionRow {
                    required property string modelData
                    text: strings.t("option." + modelData)
                    checked: root.cfg[modelData] === true
                    onToggled: {
                      var patch = {}
                      patch[modelData] = !checked
                      root.svc.update(patch)
                    }
                  }
                }
              }
            }
          }
        }

        Rectangle {
          width: columns.width
          height: 1
          color: Util.alpha(root.fg, 0.08)
        }

        // Every key the panel answers to, as keycaps in two centred rows.
        Column {
          width: columns.width
          spacing: Style.space(7)

          Repeater {
            model: [
              [["Space", "toggle"], ["S", "skip"], ["R", "reset"], ["1 2", "phase"], ["E", "type"]],
              [["← →", "one"], ["↑ ↓", "five"], ["M", "sounds"], ["N", "mix"], ["O", "options"]]
            ]
            Row {
              required property var modelData
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(14)
              Repeater {
                model: modelData
                KeyHint {
                  required property var modelData
                  key: modelData[0]
                  label: strings.t("key." + modelData[1])
                }
              }
            }
          }
        }
      }
    }
  }
}
