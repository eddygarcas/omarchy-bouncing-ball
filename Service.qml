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
  property real gravity: 900
  property real rotation: 0
  property real viewportWidth: 1920
  property real viewportHeight: 1080

  // "orbit" mode only: the live cursor position (in THIS window's own
  // local/viewport space, not Hyprland's global one -- see screenOffsetX/Y
  // below), the point it orbits -- see Model.js's step() docblock for the
  // actual attraction math. The overlay is deliberately click-through (see
  // the keyboard-focus block comment in Overlay.qml for why that matters),
  // so it never holds pointer focus and can't get continuous Wayland
  // mouse-move events outside its own tiny hitbox -- hyprctl's own IPC
  // socket is the sanctioned way to read the compositor's live cursor
  // position without grabbing it. Polled well under the 60Hz physics tick
  // (30/s, decoupled like maskSyncTimer already is) since a subprocess
  // spawn per tick would be wasteful; only runs at all while this mode is
  // actually selected and bouncing.
  property real cursorX: viewportWidth / 2
  property real cursorY: viewportHeight / 2

  // `hyprctl cursorpos` answers in Hyprland's GLOBAL (all-monitors)
  // coordinate space, but x/y/viewportWidth/viewportHeight here are all
  // local to whichever single output this overlay is anchored to -- on
  // anything but a single monitor pinned at (0,0), the raw reply lands
  // outside [0, viewportWidth]x[0, viewportHeight] and orbit mode would
  // aim at a point that isn't even on screen. Set once by Overlay.qml from
  // `window.screen.x/y` (that output's own global origin) and subtracted
  // below to convert into local space before it's ever stored.
  property real screenOffsetX: 0
  property real screenOffsetY: 0

  property Timer cursorPollTimer: Timer {
    interval: 33
    running: root.enabled && root.mode === "orbit"
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!cursorPollProcess.running) cursorPollProcess.running = true
  }

  property Process cursorPollProcess: Process {
    // Bound at the pipe with `head -c` -- a legit `cursorpos` reply is a
    // couple dozen bytes; capping well above that (not in the collector,
    // which has no size limit of its own) keeps a misbehaving/compromised
    // hyprctl from growing this persistent shell's memory unbounded.
    command: ["sh", "-c", "exec hyprctl -j cursorpos | head -c 4096"]
    stdout: StdioCollector { id: cursorPollStdout; waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      try {
        var pos = JSON.parse(cursorPollStdout.text)
        if (typeof pos.x === "number") root.cursorX = pos.x - root.screenOffsetX
        if (typeof pos.y === "number") root.cursorY = pos.y - root.screenOffsetY
      } catch (e) {
        // A malformed/empty reply just skips this tick's update -- the next
        // poll 33ms later self-corrects, not worth logging for a toy.
      }
    }
  }

  // "landing" mode only: held-key thrust state, driven by Overlay.qml's
  // keyboard handling (which only grabs keyboard focus while this mode is
  // selected and the ball is bouncing -- see WlrLayershell.keyboardFocus
  // there). landingResult is "" while airborne/undecided, else "success" or
  // "crash" -- see Model.js's step() docblock for exactly when it's set.
  property bool thrustUp: false
  property bool thrustLeft: false
  property bool thrustRight: false
  property string landingResult: ""

  // Safety net for a key release Overlay.qml's keyboard handler might miss
  // (e.g. the mode is switched away mid-thrust, taking keyboard focus with
  // it before a key-up ever arrives) -- never leave a thrust flag stuck on.
  onModeChanged: {
    root.thrustUp = false
    root.thrustLeft = false
    root.thrustRight = false
  }

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
    if (root.mode === "landing") {
      // A fair, controlled start -- no random sideways kick to fight before
      // the player has even touched a key, unlike the other two modes.
      root.vx = 0
      root.vy = 0
      root.landingResult = ""
    } else if (root.mode === "orbit") {
      // A radial kick would just dive straight into the attractor and get
      // slingshot out unpredictably -- a TANGENTIAL kick (perpendicular to
      // the line from the ball to the cursor) is what actually makes it
      // orbit instead of collide, same as giving a satellite sideways
      // velocity instead of dropping it straight down.
      var dx0 = root.cursorX - (root.x + root.size / 2)
      var dy0 = root.cursorY - (root.y + root.size / 2)
      var r0 = Math.max(1, Math.hypot(dx0, dy0))
      root.vx = -(dy0 / r0) * root.speed
      root.vy = (dx0 / r0) * root.speed
    } else {
      root.vx = v.vx
      root.vy = root.mode === "gravity" ? 0 : v.vy
    }
    root.enabled = true
  }

  function stop() {
    root.enabled = false
    root.keepAwake = false
    root.keepAwakeEndsAt = 0
    root.thrustUp = false
    root.thrustLeft = false
    root.thrustRight = false
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
    // Bound at the pipe with `head -c`, same reasoning as cursorPollProcess
    // above -- PATH_MAX is 4096 on Linux, so a legit picked path never gets
    // near the cap. `$1` keeps the target dir out of shell interpolation.
    imagePickerProcess.command = ["sh", "-c", "exec omarchy-menu-images \"$1\" | head -c 4096", "sh", Quickshell.env("HOME") + "/Pictures"]
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
      size: root.size, mode: root.mode, gravity: root.gravity,
      width: root.viewportWidth, height: root.viewportHeight,
      thrustUp: root.thrustUp, thrustLeft: root.thrustLeft, thrustRight: root.thrustRight,
      landingResult: root.landingResult,
      attractorX: root.cursorX, attractorY: root.cursorY
    }, dt)
    root.x = next.x
    root.y = next.y
    root.vx = next.vx
    root.vy = next.vy
    root.landingResult = next.landingResult
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
        size: root.size, style: root.style, mode: root.mode, gravity: root.gravity,
        viewportWidth: root.viewportWidth, viewportHeight: root.viewportHeight,
        keepAwake: root.keepAwake,
        keepAwakeMinutes: root.keepAwakeMinutes,
        keepAwakeEndsAt: root.keepAwakeEndsAt,
        imagePath: root.imagePath,
        imagePickerRunning: root.imagePickerRunning,
        thrustUp: root.thrustUp,
        thrustLeft: root.thrustLeft,
        thrustRight: root.thrustRight,
        landingResult: root.landingResult,
        cursorX: root.cursorX,
        cursorY: root.cursorY
      })
    }
    // Mirror what the settings panel's buttons already do, so a keybinding
    // or script can drive the same knobs.
    function setSize(value: string): string { root.size = Number(value); return String(root.size) }
    function setMode(value: string): string { root.mode = value; return root.mode }
    function setGravity(value: string): string { root.gravity = Number(value); return String(root.gravity) }
    function setStyle(value: string): string { root.style = value; return root.style }
    function setSpeedIpc(value: string): string { root.setSpeed(Number(value)); return String(root.speed) }
    function keepAwakeStart(value: string): string { root.startKeepAwake(Number(value)); return String(root.keepAwakeMinutes) }
    function keepAwakeStop(): string { root.stopKeepAwake(); return "stopped" }
    function pickImage(): string { root.pickImage(); return root.imagePickerRunning ? "picking" : "busy" }
  }
}
