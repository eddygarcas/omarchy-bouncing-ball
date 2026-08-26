import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  // Injected by omarchy-shell: the sibling Service.qml instance for this
  // plugin id, handed over automatically because this kind pairs with a
  // "service" kind in the same manifest.
  property var service: null

  PanelWindow {
    id: window
    visible: !!(root.service && root.service.enabled)
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "eduard-bouncing-ball"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // The clickable input region tracks the ball's bounding box via
    // `hitboxAnchor`, not the visual `canvas` directly, so the rest of the
    // screen stays click-through. Region{item:...} pushes a fresh Wayland
    // input-region update whenever the tracked item's geometry changes;
    // syncing to a slow stand-in instead of canvas (which moves every 60Hz
    // physics tick) keeps that update rate down without needing canvas
    // itself to move any less smoothly.
    mask: Region { item: hitboxAnchor }

    // Backs the "Keep Awake" panel toggle: this is the standard Wayland
    // idle-inhibit-v1 protocol, which the built-in idle/lock service already
    // respects (its IdleMonitor runs with respectInhibitors: true) -- so
    // enabling this is enough to block screensaver/lock/suspend system-wide,
    // with no need to reach into that other service's own state.
    IdleInhibitor {
      window: window
      enabled: !!(root.service && root.service.keepAwake && root.service.enabled)
    }

    onWidthChanged: if (root.service) root.service.viewportWidth = width
    onHeightChanged: if (root.service) root.service.viewportHeight = height
    Component.onCompleted: {
      if (!root.service) return
      root.service.viewportWidth = width
      root.service.viewportHeight = height
    }

    // Stand-in the input-region mask tracks instead of the fast-moving
    // canvas -- see the comment on `mask` above. Position is copied over
    // imperatively by maskSyncTimer, not bound reactively, which is the
    // part that actually decouples it from the 60Hz physics loop.
    Item {
      id: hitboxAnchor
      width: root.service ? root.service.size : 0
      height: root.service ? root.service.size : 0
    }

    Timer {
      id: maskSyncTimer
      interval: 66
      running: !!(root.service && root.service.enabled)
      repeat: true
      triggeredOnStart: true
      onTriggered: {
        hitboxAnchor.x = canvas.x
        hitboxAnchor.y = canvas.y
      }
    }

    // Backs the "image" style: the source texture wrapped around the ball
    // in Model.drawImageSphere. Loaded via the QML Image element (not
    // Canvas.loadImage(url)) so its natural pixel size is available as
    // sourceSize -- the equirectangular source-rect math needs real pixels,
    // not the destination canvas size.
    Image {
      id: textureImage
      visible: false
      asynchronous: true
      cache: true
      source: root.service && root.service.style === "image" && root.service.imagePath
        ? Util.fileUrl(root.service.imagePath)
        : ""
      onStatusChanged: {
        if (status === Image.Ready) {
          colorSampleCanvas.avgColor = ""
          colorSampleCanvas.requestPaint()
        }
        canvas.requestPaint()
      }
    }

    // Samples the just-loaded image's BACKGROUND color ONCE per image pick,
    // for drawImageSphere's un-decaled-hemisphere fallback fill (see its
    // docblock in Model.js) -- not a per-frame per-pixel reconstruction of
    // the sphere, which is the thing this plugin's history says never to
    // reintroduce (see Model.js's note on the old createImageData/
    // putImageData approach freezing the whole shell). A single getImageData
    // read of a tiny downscaled canvas, done once when an image is picked,
    // is a fundamentally different cost than that.
    //
    // Averages only the outermost ring of pixels, not the whole image: a
    // typical picked photo is a subject (here, a ball) roughly centered
    // against a plain backdrop, so the backdrop is what reaches the edges
    // while the subject usually doesn't. Averaging every pixel instead
    // pulled the result toward whatever color the subject itself was
    // (e.g. a red/white checker ball averaging to a muted pink) rather than
    // the actual background behind it (plain white, for that same photo).
    // 32x32, not smaller: at 16x16 each border pixel is a bilinear blend of
    // a 16x16 block of source pixels, which was close enough to the ball's
    // silhouette in a test photo to still smudge red into the "background"
    // read -- 32x32 halves that per-pixel source footprint and landed on
    // the actual background color cleanly. Still a one-shot cost, not a
    // per-frame one.
    Canvas {
      id: colorSampleCanvas
      visible: false
      width: 32
      height: 32
      property string avgColor: ""

      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.drawImage(textureImage, 0, 0, width, height)
        var data
        try {
          data = ctx.getImageData(0, 0, width, height).data
        } catch (e) {
          return
        }
        var r = 0, g = 0, b = 0, alphaSum = 0, pixelCount = 0
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            if (x !== 0 && x !== width - 1 && y !== 0 && y !== height - 1) continue
            var i = (y * width + x) * 4
            var a = data[i + 3]
            r += data[i] * a
            g += data[i + 1] * a
            b += data[i + 2] * a
            alphaSum += a
            pixelCount++
          }
        }
        // QtQuick's Canvas has a history of silently dropping drawImage
        // calls (see Model.js) -- a near-zero alpha sum means this paint
        // was one of them, not that the image is mostly transparent, so
        // leave avgColor unset rather than reporting black as the average.
        if (alphaSum < pixelCount * 8) return
        avgColor = "rgb(" + Math.round(r / alphaSum) + "," + Math.round(g / alphaSum) + "," + Math.round(b / alphaSum) + ")"
      }

      onAvgColorChanged: canvas.requestPaint()
    }

    Canvas {
      id: canvas
      visible: !!(root.service && root.service.enabled)
      width: root.service ? root.service.size : 0
      height: root.service ? root.service.size : 0
      x: root.service ? root.service.x : 0
      y: root.service ? root.service.y : 0

      onPaint: {
        if (!root.service) return
        var ctx = getContext("2d")
        var useImage = root.service.style === "image" && textureImage.status === Image.Ready
        Model.drawBall(
          ctx, root.service.size, root.service.style, root.service.color, root.service.rotation,
          useImage ? textureImage : null,
          useImage ? textureImage.sourceSize.width : 0,
          useImage ? textureImage.sourceSize.height : 0,
          colorSampleCanvas.avgColor
        )
      }

      // Position (x/y) updates every physics tick via plain item bindings
      // above, which the scene graph handles as a cheap transform -- no
      // repaint needed for motion alone. Repainting the canvas *contents*
      // (the spin, in particular) only needs to happen often enough to look
      // smooth, not on every single 60Hz physics tick, so it's throttled
      // here to a fixed ~24fps independent of the physics rate.
      Timer {
        interval: 42
        running: !!(root.service && root.service.enabled)
        repeat: true
        onTriggered: canvas.requestPaint()
      }

      Connections {
        target: root.service
        function onStyleChanged() { canvas.requestPaint() }
        function onColorChanged() { canvas.requestPaint() }
        function onSizeChanged() { canvas.requestPaint() }
        function onImagePathChanged() { canvas.requestPaint() }
      }

      // Click the ball to boop it back into the air -- offset from center
      // is passed through so a swat to one side sends it the other way.
      // Distance-check against the radius so the mask's square corners
      // (outside the visually round ball) don't count as a hit.
      MouseArea {
        anchors.fill: parent
        onClicked: function(mouse) {
          if (!root.service) return
          var r = canvas.width / 2
          var dx = mouse.x - r
          var dy = mouse.y - r
          if (dx * dx + dy * dy > r * r) return
          root.service.hit(dx, dy)
        }
      }
    }
  }
}
