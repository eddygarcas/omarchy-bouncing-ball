# Bouncing Ball

A customizable ball that bounces around your screen, [Amiga Boing
Ball](https://en.wikipedia.org/wiki/Amiga_Boing_Ball)-style, for
[Omarchy](https://omarchy.org/). Click the bar icon to start/stop it and
tweak its style, size, speed, and physics; click the ball itself to boop it
back into the air. It doubles as a "keep awake" tool: an optional mode
bounces the ball as a visible reminder while blocking your screen from
locking, sleeping, or dimming, for a duration you set with a slider.

## Install

```
omarchy plugin add https://github.com/eddygarcas/omarchy-bouncing-ball.git --enable
```

Or manually:

```
git clone https://github.com/eddygarcas/omarchy-bouncing-ball.git \
  ~/.config/omarchy/plugins/eduard.bouncing-ball
omarchy-shell shell rescanPlugins
omarchy plugin enable eduard.bouncing-ball
```

## Remove

```
omarchy plugin remove eduard.bouncing-ball
```

This deletes `~/.config/omarchy/plugins/eduard.bouncing-ball/` and removes
the widget from your bar layout. There's nothing else to clean up: settings
are in-memory only (see below), and the plugin writes no files and starts no
external processes.

## What it does

Click the bar icon (a plain circle) to open the panel:

- **Bounce!** — starts/stops the ball.
- **Style** — Amiga (red/white checker sphere), Solid (pick from 6 colors),
  or Rainbow (continuously cycling hue).
- **Size** — S / M / L / XL.
- **Speed** — Chill / Normal / Fast / Turbo.
- **Physics** — Classic bounce (constant velocity, bounces off all four
  edges forever, DVD-logo style) or Gravity drop (falls, loses energy each
  bounce, eventually settles and rolls along the floor).
- **Keep Awake** — a toggle plus a slider (0 to 3 hours, in 5-minute steps;
  0 means "until you turn it off"). Turning it on starts the ball bouncing
  if it isn't already and inhibits the system idle cycle for the chosen
  duration, so the screensaver, lock, and auto-suspend won't fire — handy
  for watching a long build finish or a video call without input. It stops
  itself automatically when the timer runs out, or turn it off (or hit
  **Bounce!**) to end it early. Dragging the slider while it's already on
  re-arms the countdown immediately with the new duration.

Click the ball itself at any point to boop it — it kicks upward and nudges
sideways *away* from wherever you clicked, like batting a real ball. That
works whether it's mid-bounce or has already settled at the bottom in
Gravity mode, so repeated clicking is how you keep it going.

It renders as a full-screen, click-through overlay (the same technique
Omarchy's own on-screen-display uses): everywhere except the ball itself
stays click-through, so it never blocks the desktop underneath it. A
background service owns the physics so it keeps running independently of
whether the settings panel is open.

Keep Awake works through the standard Wayland `idle-inhibit-v1` protocol
(Quickshell's `IdleInhibitor`, attached to the overlay window) rather than
touching Omarchy's own idle/lock settings or its separate built-in "Stay
Awake" indicator — Omarchy's idle service already runs its idle detection
with `respectInhibitors: true`, so this is the same mechanism any other
idle-inhibiting app (a video player, a video call client) would use, and it
stays fully self-contained: nothing outside this plugin's own state changes,
and nothing persists once it's off.

## Known limitations

- **Single monitor.** It bounces on whichever screen its overlay window
  lands on; there's no per-monitor roaming.
- **Settings don't persist** across `omarchy restart shell` — resets to
  Amiga / Medium / Normal / Classic bounce each time. In-memory only, no
  config file, since this is a toy rather than something worth persisting.
- **The Amiga checker isn't a pixel-exact sphere projection**, but it's
  close. Latitude bands are spaced by `r*sin(latitude)` so they genuinely
  compress near the top/bottom like a real sphere's foreshortening, and each
  wedge's left/right edges are sampled along the actual projected meridian
  ellipse (`x = r*sin(theta)*cos(phi)`, `y = r*sin(phi)`) instead of
  straight radii to the center, so the checker pattern reads as a wrapped
  sphere rather than a pinwheel. Wedges whose entire longitude span faces
  away from the viewer (`cos(theta) < 0`) are culled before drawing --
  without that, front and back wedges land on the exact same screen pixels
  under orthographic projection, and painter's-order overdraw made the two
  halves of the ball appear to spin in opposite directions as `phase`
  advanced. The remaining inexactness is just the sampling: each meridian
  edge is approximated with a handful of line segments rather than a true
  curve, which is visually indistinguishable at the current band count but
  would show as faceting if `latBands`/`meridianSamples` were lowered a lot.
- **Do not reintroduce per-pixel canvas rendering for the Amiga texture.**
  An earlier version used `createImageData`/`putImageData` to reconstruct
  each pixel's 3D position for a mathematically exact sphere projection. It
  looked right, but reliably froze the entire Omarchy shell after roughly
  15-25 seconds of continuous repainting -- confirmed via CPU-monitored soak
  tests, independent of texture resolution, throttling, or the input-region
  mask. The current implementation avoids that path entirely, drawing only
  with vector primitives (`arc`/`clip`/`fillRect`/`moveTo`/`lineTo`, the
  same kind used everywhere else in this plugin, soak-tested clean at 45+
  seconds continuous with flat CPU). If you improve the sphere accuracy,
  keep it on that side of the line.

## Permissions & dependencies

- No external packages or network access required.
- Runs entirely inside the shared `omarchy-shell` process via a background
  service, a bar-widget settings panel, and a full-screen click-through
  overlay -- no separate processes, no files written to disk.
- Keep Awake uses the standard Wayland `idle-inhibit-v1` protocol (via
  Quickshell's `IdleInhibitor`) to block screensaver/lock/suspend while it's
  on -- the same mechanism any idle-inhibiting app uses, not a custom
  workaround. It only takes effect while this plugin's overlay window is
  visible and Keep Awake is toggled on, and stops the moment either is off.
- Like every Quickshell plugin, this code runs unsandboxed inside that
  shared process -- review `Panel.qml` / `Service.qml` / `Overlay.qml` /
  `Model.js` before installing.

## Files

| File           | Purpose                                                        |
|----------------|-----------------------------------------------------------------|
| `manifest.json`| Plugin manifest (`service` + `bar-widget` + `overlay`)          |
| `Panel.qml`    | Bar icon + settings panel                                       |
| `Service.qml`  | Background physics state (position, velocity, style, IPC)       |
| `Overlay.qml`  | Full-screen click-through window that renders the ball          |
| `Model.js`     | Presets, physics step function, and the ball-drawing routines   |

## License

MIT — see [LICENSE](LICENSE).
