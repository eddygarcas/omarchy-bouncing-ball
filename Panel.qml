import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "eduard.bouncing-ball"
  ipcTarget: moduleName

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor(root.moduleName) : null
  readonly property bool bouncing: !!(svc && svc.enabled)

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    slotSize: Style.bar.iconSlot
    tooltipText: "Bouncing ball"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero ----------
        Row {
          width: parent.width
          spacing: Style.space(12)

          Text {
            text: ""
            color: root.svc ? root.svc.color : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            spacing: Style.space(2)
            anchors.verticalCenter: parent.verticalCenter

            Text {
              text: "Bouncing Ball"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: root.bouncing ? "BOUNCING" : "STOPPED"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Toggle {
          width: parent.width
          label: "Bounce!"
          description: root.bouncing
            ? "Roaming your screen right now. Flip off to send it home."
            : "Off. Flip on to let it loose."
          checked: root.bouncing
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: if (root.svc) root.svc.toggle()
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Keep Awake ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "KEEP AWAKE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          // Ticks once a second so the "stops in..." description below stays
          // live without a reactive clock property on the service itself.
          // Only runs while the panel is open and there's an actual deadline
          // to count down to.
          Timer {
            id: keepAwakeTick
            property int tick: 0
            interval: 1000
            repeat: true
            running: panel.open && !!(root.svc && root.svc.keepAwake && root.svc.keepAwakeEndsAt > 0)
            onTriggered: tick++
          }

          Toggle {
            width: parent.width
            label: "Keep Awake"
            description: {
              keepAwakeTick.tick // establishes the binding that keeps this live
              if (!root.svc || !root.svc.keepAwake) {
                return "Off. Bounces the ball and blocks your screen from sleeping or locking for the duration below."
              }
              if (root.svc.keepAwakeEndsAt <= 0) return "On — blocking sleep/lock until you turn this off."
              return "On — blocking sleep/lock, stops in " + Model.formatRemainingMs(root.svc.keepAwakeEndsAt - Date.now()) + "."
            }
            checked: !!(root.svc && root.svc.keepAwake)
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: if (root.svc) root.svc.toggleKeepAwake()
          }

          PanelSlider {
            id: keepAwakeSlider
            bar: root.bar
            width: parent.width
            minimum: 0
            maximum: 180
            step: 5
            integer: true
            value: root.svc ? root.svc.keepAwakeMinutes : 30
            onMoved: function(v) { if (root.svc) root.svc.keepAwakeMinutes = v }
            onReleased: function(v) {
              if (!root.svc) return
              root.svc.keepAwakeMinutes = v
              // Re-arm a countdown already in flight so dragging the slider
              // while Keep Awake is on takes effect immediately instead of
              // only applying the next time it's turned on.
              if (root.svc.keepAwake) root.svc.startKeepAwake(v)
            }
          }

          Text {
            text: "Duration: " + (root.svc ? Model.formatMinutes(root.svc.keepAwakeMinutes) : "30m")
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Style ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "STYLE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: Model.stylePresets
              Button {
                required property var modelData
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                active: root.svc && root.svc.style === modelData.value
                onClicked: if (root.svc) root.svc.style = modelData.value
              }
            }
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)
            visible: root.svc && root.svc.style === "solid"

            Repeater {
              model: Model.colorSwatches
              Button {
                required property var modelData
                width: Style.space(28)
                height: Style.space(28)
                background: modelData
                bordered: true
                active: root.svc && root.svc.color === modelData
                onClicked: if (root.svc) root.svc.color = modelData
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.svc && root.svc.style === "image"

            Button {
              width: parent.width
              leftAlign: true
              text: root.svc && root.svc.imagePickerRunning
                ? "Choosing…"
                : (root.svc && root.svc.imagePath ? "Change Image…" : "Choose Image…")
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              enabled: !(root.svc && root.svc.imagePickerRunning)
              opacity: enabled ? 1.0 : 0.6
              onClicked: if (root.svc) root.svc.pickImage()
            }

            Text {
              visible: !!(root.svc && root.svc.imagePath)
              text: root.svc ? root.svc.imagePath.split("/").pop() : ""
              textFormat: Text.PlainText
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
              width: parent.width
            }
          }
        }

        // ---------- Size ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "SIZE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: Model.sizePresets
              Button {
                required property var modelData
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                active: root.svc && root.svc.size === modelData.size
                onClicked: if (root.svc) root.svc.size = modelData.size
              }
            }
          }
        }

        // ---------- Speed ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "SPEED"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: Model.speedPresets
              Button {
                required property var modelData
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                active: root.svc && root.svc.speed === modelData.speed
                onClicked: if (root.svc) root.svc.setSpeed(modelData.speed)
              }
            }
          }
        }

        // ---------- Physics ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "PHYSICS"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: Model.physicsPresets
              Button {
                required property var modelData
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                active: root.svc && root.svc.mode === modelData.value
                onClicked: if (root.svc) root.svc.mode = modelData.value
              }
            }
          }

          // Gravity drop, Landing, and Zero-G Orbit all apply gravity -- see
          // Model.js's step(). The slider gives free control over the exact
          // value; the preset buttons below jump straight to Moon/Mars/Earth
          // and -- via the same `active` highlight every other preset row in
          // this panel already uses -- double as a check for whether the
          // slider is currently sitting exactly on one of them.
          Column {
            visible: !!(root.svc && (root.svc.mode === "gravity" || root.svc.mode === "landing" || root.svc.mode === "orbit"))
            width: parent.width
            spacing: Style.space(6)

            PanelSlider {
              bar: root.bar
              width: parent.width
              minimum: 50
              maximum: 2000
              step: 10
              integer: true
              value: root.svc ? root.svc.gravity : 900
              onMoved: function(v) { if (root.svc) root.svc.gravity = v }
              onReleased: function(v) { if (root.svc) root.svc.gravity = v }
            }

            Text {
              text: {
                if (!root.svc) return ""
                var match = Model.gravityPresets.find(function(p) { return p.gravity === root.svc.gravity })
                return Math.round(root.svc.gravity) + " px/s²" + (match ? " · " + match.label : "")
              }
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: Model.gravityPresets
                Button {
                  required property var modelData
                  text: modelData.label
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  bordered: true
                  active: root.svc && root.svc.gravity === modelData.gravity
                  onClicked: if (root.svc) root.svc.gravity = modelData.gravity
                }
              }
            }
          }

          // Landing has no on-screen HUD of its own (the overlay is a
          // click-through canvas, not a full app window) -- this is the
          // only place the controls and the current attempt's outcome are
          // shown, so it doubles as both the instructions and the result.
          Text {
            visible: !!(root.svc && root.svc.mode === "landing")
            width: parent.width
            wrapMode: Text.WordWrap
            text: {
              if (!root.svc) return ""
              if (root.svc.landingResult === "success") return "🛬 Landed! Click the ball, then hold ↑ to lift off for another try."
              if (root.svc.landingResult === "crash") return "💥 Crashed — click the ball, then hold ↑ to try again."
              return "Click the ball to take control: ↑ thrusts up · ← → steer sideways. Touch down gently to land. Click elsewhere to let go again."
            }
            color: root.svc && root.svc.landingResult === "crash" ? "#e6392b"
              : root.svc && root.svc.landingResult === "success" ? "#16a085"
              : Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: !!(root.svc && root.svc.mode === "orbit")
            width: parent.width
            wrapMode: Text.WordWrap
            text: "The ball orbits your mouse cursor instead of falling -- move your mouse to relocate the pull. Higher Gravity below means a tighter, faster orbit; a close pass slingshots hard, same as a real gravity well."
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
