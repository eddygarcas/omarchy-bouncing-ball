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
      onStatusChanged: if (status === Image.Ready) canvas.requestPaint()
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
          useImage ? textureImage.sourceSize.height : 0
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
