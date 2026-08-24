import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Shared physics/appearance state for the Bouncing Ball plugin. The bar
// widget (Panel.qml) writes settings into this instance; the full-screen
// overlay (Overlay.qml) reads position/appearance out of it every frame.
// Both reach it the same way: bar.shell.serviceFor("eduard.bouncing-ball").
//
// Settings are in-memory only and reset to defaults on shell restart -- this
// is a toy, not something worth a config file for.
QtObject {
  id: root

  property bool enabled: false
  property real x: 200
  property real y: 200
  property real vx: 260
  property real vy: 0
  property real size: 90
  property real speed: 260
  property string style: "amiga"
  property string color: "#e6392b"
  property string mode: "classic"
  property real rotation: 0
  property real viewportWidth: 1920
  property real viewportHeight: 1080

  function start() {
    var v = Model.randomVelocity(root.speed)
    root.x = Math.max(0, root.viewportWidth / 2 - root.size / 2)
    root.y = Math.max(0, root.viewportHeight / 3)
    root.vx = v.vx
    root.vy = root.mode === "gravity" ? 0 : v.vy
    root.enabled = true
  }

  function stop() {
    root.enabled = false
  }

  function toggle() {
    if (root.enabled) root.stop()
    else root.start()
  }

  function setSpeed(value) {
    root.speed = value
    if (root.enabled) {
      var scale = value / Math.max(1, Math.hypot(root.vx, root.vy))
      root.vx *= scale
      root.vy *= scale
    }
  }

  // Boop the ball, like batting a real one back into the air. offsetX/offsetY
  // are where inside the ball it was clicked, relative to its center, so a
  // swat off to one side sends it the other way instead of straight up every
  // time. Works whether it's mid-bounce or has settled on the floor in
  // gravity mode -- either way, clicking sends it back up from wherever it
  // currently rests.
  function hit(offsetX, offsetY) {
    if (!root.enabled) return
    var kick = Math.max(500, root.speed * 1.6)
    root.vy = -kick
    var half = Math.max(1, root.size / 2)
    root.vx += -(offsetX / half) * kick * 0.5
  }

  function step(dt) {
    if (!root.enabled) return
    var next = Model.step({
      x: root.x, y: root.y, vx: root.vx, vy: root.vy,
      size: root.size, mode: root.mode,
      width: root.viewportWidth, height: root.viewportHeight
    }, dt)
    root.x = next.x
    root.y = next.y
    root.vx = next.vx
    root.vy = next.vy
    root.rotation = (root.rotation + root.vx * dt * 0.6) % 360
  }

  property Timer physicsTimer: Timer {
    interval: 16
    running: root.enabled
    repeat: true
    onTriggered: root.step(interval / 1000)
  }

  // Lets a keybinding drive the ball too, e.g.:
  //   omarchy-shell eduard.ball toggle
  property var ipc: IpcHandler {
    target: "eduard.ball"
    function start(): string { root.start(); return "bouncing" }
    function stop(): string { root.stop(); return "stopped" }
    function toggle(): string { root.toggle(); return root.enabled ? "bouncing" : "stopped" }
    function status(): string {
      return JSON.stringify({
        state: root.enabled ? "bouncing" : "stopped",
        x: root.x, y: root.y, vx: root.vx, vy: root.vy,
        size: root.size, style: root.style, mode: root.mode,
        viewportWidth: root.viewportWidth, viewportHeight: root.viewportHeight
      })
    }
    // Mirror what the settings panel's buttons already do, so a keybinding
    // or script can drive the same knobs.
    function setSize(value: string): string { root.size = Number(value); return String(root.size) }
    function setMode(value: string): string { root.mode = value; return root.mode }
    function setStyle(value: string): string { root.style = value; return root.style }
    function setSpeedIpc(value: string): string { root.setSpeed(Number(value)); return String(root.speed) }
  }
}
