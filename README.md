# Bouncing Ball

A customizable ball that bounces around your screen, [Amiga Boing
Ball](https://en.wikipedia.org/wiki/Amiga_Boing_Ball)-style, for
[Omarchy](https://omarchy.org/). Click the bar icon to start/stop it and
tweak its style, size, speed, and physics; click the ball itself to boop it
back into the air.

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

Click the ball itself at any point to boop it — it kicks upward and nudges
sideways *away* from wherever you clicked, like batting a real ball. That
works whether it's mid-bounce or has already settled at the bottom in
Gravity mode, so repeated clicking is how you keep it going.

It renders as a full-screen, click-through overlay (the same technique
Omarchy's own on-screen-display uses): everywhere except the ball itself
stays click-through, so it never blocks the desktop underneath it. A
background service owns the physics so it keeps running independently of
whether the settings panel is open.

## Known limitations

- **Single monitor.** It bounces on whichever screen its overlay window
  lands on; there's no per-monitor roaming.
- **Settings don't persist** across `omarchy restart shell` — resets to
  Amiga / Medium / Normal / Classic bounce each time. In-memory only, no
  config file, since this is a toy rather than something worth persisting.
- **The Amiga checker isn't a pixel-exact sphere projection.** Latitude
  bands are spaced by `r*sin(latitude)` so they genuinely compress near the
  top/bottom like a real sphere's foreshortening, and the longitude wedges
  rotate with the ball so the pattern stays fixed to its surface as it
  spins. But the wedges are pie slices from the center, which converge to a
  point rather than following true projected meridian curves — so the
  middle bands read more "pinwheel" than "grid." A fully accurate version is
  possible with more involved vector math (projected meridian arcs instead
  of straight radii); not attempted yet.
- **Do not reintroduce per-pixel canvas rendering for the Amiga texture.**
  An earlier version used `createImageData`/`putImageData` to reconstruct
  each pixel's 3D position for a mathematically exact sphere projection. It
  looked right, but reliably froze the entire Omarchy shell after roughly
  15-25 seconds of continuous repainting -- confirmed via CPU-monitored soak
  tests, independent of texture resolution, throttling, or the input-region
  mask. The current implementation avoids that path entirely, drawing only
  with `arc`/`clip`/`fillRect` (the same primitives used everywhere else in
  this plugin, soak-tested clean at 45+ seconds continuous with flat CPU).
  If you improve the sphere accuracy, keep it on that side of the line.

## Permissions & dependencies

- No external packages or network access required.
- Runs entirely inside the shared `omarchy-shell` process via a background
  service, a bar-widget settings panel, and a full-screen click-through
  overlay -- no separate processes, no files written to disk.
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
