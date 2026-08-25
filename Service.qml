import QtQuick
import Quickshell
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

  // Absolute path to the image last picked for the "image" style. Chosen via
  // pickImage(), which shells out to Omarchy's own image picker rather than
  // reimplementing a file browser -- see the Process below.
  property string imagePath: ""
  property bool imagePickerRunning: false

  // Keep Awake: an opt-in mode that bounces the ball (as a visible "why is
  // my screen still on" indicator) while inhibiting the system idle
  // cycle -- see the IdleInhibitor bound to the overlay window in
  // Overlay.qml, which is what actually blocks the built-in idle/lock
  // service (that service's IdleMonitor runs with respectInhibitors: true
  // for exactly this purpose). keepAwakeMinutes is the slider's last set
  // duration; keepAwakeEndsAt is 0 for "no timer, run until stopped" or an
  // absolute Date.now()-based deadline otherwise.
  property bool keepAwake: false
  property int keepAwakeMinutes: 30
  property double keepAwakeEndsAt: 0

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
    root.keepAwake = false
    root.keepAwakeEndsAt = 0
  }

  function toggle() {
    if (root.enabled) root.stop()
    else root.start()
  }

  // Starting Keep Awake bounces the ball if it isn't already, without
  // resetting one already in flight. `minutes` <= 0 means no auto-stop.
  function startKeepAwake(minutes) {
    var m = Math.max(0, Math.round(Number(minutes) || 0))
    root.keepAwakeMinutes = m
    root.keepAwake = true
    root.keepAwakeEndsAt = m > 0 ? Date.now() + m * 60000 : 0
    if (!root.enabled) root.start()
  }

  // Turns off idle-inhibiting but leaves the ball itself bouncing --
  // stopping the ball entirely is what `stop()` is for.
  function stopKeepAwake() {
    root.keepAwake = false
    root.keepAwakeEndsAt = 0
  }

  function toggleKeepAwake() {
    if (root.keepAwake) root.stopKeepAwake()
    else root.startKeepAwake(root.keepAwakeMinutes)
  }

  // Opens Omarchy's own image picker (the same fullscreen carousel used for
  // wallpapers/themes) pointed at ~/Pictures, rather than this plugin
  // reimplementing a file browser. `omarchy-menu-images` owns the whole
  // summon/select/wait dance and just blocks until it can print the chosen
  // path (or nothing, if cancelled) -- safe to shell out to since it's a
  // separate process, not something that blocks this Quickshell instance.
  function pickImage() {
    if (root.imagePickerRunning) return
    root.imagePickerRunning = true
    imagePickerProcess.command = ["omarchy-menu-images", Quickshell.env("HOME") + "/Pictures"]
    imagePickerProcess.running = true
  }

  property Process imagePickerProcess: Process {
    stdout: StdioCollector { id: imagePickerStdout; waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      root.imagePickerRunning = false
      var path = imagePickerStdout.text ? imagePickerStdout.text.trim() : ""
      if (path.length > 0) {
        root.imagePath = path
        root.style = "image"
      }
    }
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

  // Polls for the Keep Awake deadline rather than firing a one-shot Timer at
  // the exact remaining interval, so changing keepAwakeEndsAt mid-countdown
  // (the panel's slider re-arms it live) never needs to touch a Timer's own
  // running/interval bookkeeping -- it just changes what this check compares
  // against next tick.
  property Timer keepAwakeDeadlineTimer: Timer {
    interval: 1000
    running: root.keepAwake && root.keepAwakeEndsAt > 0
    repeat: true
    onTriggered: {
      if (Date.now() >= root.keepAwakeEndsAt) root.stop()
    }
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
        viewportWidth: root.viewportWidth, viewportHeight: root.viewportHeight,
        keepAwake: root.keepAwake,
        keepAwakeMinutes: root.keepAwakeMinutes,
        keepAwakeEndsAt: root.keepAwakeEndsAt,
        imagePath: root.imagePath,
        imagePickerRunning: root.imagePickerRunning
      })
    }
    // Mirror what the settings panel's buttons already do, so a keybinding
    // or script can drive the same knobs.
    function setSize(value: string): string { root.size = Number(value); return String(root.size) }
    function setMode(value: string): string { root.mode = value; return root.mode }
    function setStyle(value: string): string { root.style = value; return root.style }
    function setSpeedIpc(value: string): string { root.setSpeed(Number(value)); return String(root.speed) }
    function keepAwakeStart(value: string): string { root.startKeepAwake(Number(value)); return String(root.keepAwakeMinutes) }
    function keepAwakeStop(): string { root.stopKeepAwake(); return "stopped" }
    function pickImage(): string { root.pickImage(); return root.imagePickerRunning ? "picking" : "busy" }
  }
}
