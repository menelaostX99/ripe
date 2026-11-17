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
  onOpenedChanged: if (!opened) showOptions = false

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
    return strings.t("length").arg(number(cfg[phase]))
  }

  function nudge(minutes) {
    svc.setMinutes(phase, Number(cfg[phase]) + minutes)
  }

  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---------------------------------------------------------------- bar

  TextMetrics {
    id: barClock
    font.family: root.fontFamily
    font.pixelSize: Style.bar.iconFont
    text: root.clockText
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar

    readonly property bool showClock: !root.idle && !root.vertical
    slotSize: Style.bar.statusSlot + (showClock ? Math.ceil(barClock.advanceWidth) + Style.space(12) : 0)
    labelText: showClock ? root.clockText : ""
    dimmed: root.paused
    tooltipText: root.opened ? "" : strings.t("tooltip")
    // A ripe tomato when idle; it empties as the session runs down.
    iconComponent: Component {
      Tomato {
        width: 16
        height: 16
        color: button.foreground
        level: root.idle ? 1 : root.remaining
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
      blocked: minutesStepper.editing

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

              Repeater {
                model: 60
                Rectangle {
                  required property int index
                  readonly property bool major: index % 5 === 0
                  // Minutes still to run stay lit; spent ones go dark.
                  readonly property bool live: root.idle || index / 60 >= 1 - root.remaining - 0.0001
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
                remaining: root.remaining
                color: Util.alpha(root.phaseColor, root.paused ? 0.5 : 1)
                trackColor: Util.alpha(root.fg, 0.09)
                // Smooths the quarter-second ticks into one steady sweep.
                Behavior on remaining { NumberAnimation { duration: Style.duration(250) } }
                Behavior on color { ColorAnimation { duration: Style.duration(200) } }
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

                Label {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.stateLabel.toUpperCase()
                  color: root.running ? root.phaseColor : root.dim
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 2
                  Behavior on color { ColorAnimation { duration: Style.duration(200) } }
                }
                Label {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.clockText
                  font.pixelSize: Style.space(root.clockText.length > 5 ? 34 : 44)
                  font.weight: Font.Light
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
                value: root.cfg[root.phase]
                from: Model.LIMITS[root.phase][0]
                to: Model.LIMITS[root.phase][1]
                suffix: strings.t("unit.min")
                foreground: root.fg
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(value) { root.svc.setMinutes(root.phase, value) }
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
                    selected: root.cfg[root.phase] === modelData
                    horizontalPadding: Style.space(9)
                    foreground: selected ? root.fg : root.dim
                    accent: root.accent
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    onClicked: root.svc.setMinutes(root.phase, modelData)
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
                visible: !root.showOptions

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
                      width: (tiles.width - tiles.spacing * (tiles.columns - 1)) / tiles.columns
                      label: strings.t("sound." + modelData)
                      icon: "file://" + root.svc.cacheDir + "/icons/" + modelData + ".svg"
                      active: root.cfg.active.indexOf(modelData) >= 0
                      sounding: active && root.svc.audible
                      level: root.cfg.levels[modelData] === undefined ? 0.6 : root.cfg.levels[modelData]
                      foreground: root.fg
                      accent: root.accent
                      fontFamily: root.fontFamily
                      onToggled: root.svc.toggleSound(modelData)
                      onLevelPicked: function(level) { root.svc.setSoundLevel(modelData, level) }
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
                visible: root.showOptions

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

        Label {
          width: columns.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          color: Util.alpha(root.fg, 0.38)
          font.pixelSize: Style.font.caption
          text: strings.t("keys")
        }
      }
    }
  }
}
