import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false
  property bool applied: false
  property var savedConfig: ({})
  property int zoom: 30
  property int moveUp: 30
  property int moveRight: 100
  property bool mode4k: true
  property string dragMode: ""
  property real dragOriginX: 0
  property real dragOriginY: 0
  property int dragZoom: 0
  property int dragMoveUp: 0
  property int dragMoveRight: 0

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  readonly property string fontFamily: Style.font.menuFamily

  readonly property var sourceSize: Model.baseSize(root.mode4k)
  readonly property var view: Model.viewport(sourceSize.w, sourceSize.h, zoom, moveUp, moveRight)
  readonly property var paint: {
    var w = previewImage.paintedWidth
    var h = previewImage.paintedHeight
    if (w <= 0 || h <= 0) return { x: 0, y: 0, w: 0, h: 0 }
    return {
      x: (previewStage.width - w) / 2,
      y: (previewStage.height - h) / 2,
      w: w,
      h: h
    }
  }
  readonly property var cropPx: {
    var tl = Model.sourceToPreview(view.x, view.y, paint, sourceSize.w, sourceSize.h)
    var br = Model.sourceToPreview(view.x + view.w, view.y + view.h, paint, sourceSize.w, sourceSize.h)
    return { x: tl.x, y: tl.y, w: Math.max(8, br.x - tl.x), h: Math.max(8, br.y - tl.y) }
  }
  readonly property string statusLine: {
    if (!service) return "Service not loaded"
    if (service.lastError) return service.lastError
    if (service.capturing) return "Capturing preview…"
    if (!service.previewUrl) return "Capturing preview…"
    return "Drag the frame to move it. Scroll or use the zoom slider to resize. Start writes this crop to Omacam."
  }

  function copyConfig(cfg) {
    var src = Model.mergeConfig(cfg || {})
    return Model.mergeConfig(src)
  }

  function loadFromService() {
    if (!service) return
    var cfg = copyConfig(service.config)
    savedConfig = copyConfig(cfg)
    zoom = cfg.zoom
    moveUp = cfg.moveUp
    moveRight = cfg.moveRight
    mode4k = cfg.mode4k === true
    applied = false
  }

  function pushDraftToService() {
    if (!service) return
    service.setMode4k(mode4k)
    service.setCrop(zoom, moveUp, moveRight)
  }

  onServiceChanged: {
    if (!opened || !service) return
    loadFromService()
    if (!service.previewUrl && typeof service.beginPreview === "function")
      service.beginPreview()
  }

  function open(payloadJson) {
    root.opened = true
    root.loadFromService()
    if (service && typeof service.beginPreview === "function") service.beginPreview()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    if (root.opened && !root.applied && root.service) {
      root.service.writeConfig(root.savedConfig)
      root.service.finishPreview(false)
    }
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "mrlund.omacam")
  }

  function applyAndStart() {
    if (!service) return
    applied = true
    pushDraftToService()
    service.writeConfig(service.config)
    service.finishPreview(true)
    root.dismiss()
  }

  function clampDraft() {
    var next = Model.viewport(sourceSize.w, sourceSize.h, zoom, moveUp, moveRight)
    zoom = Model.mergeConfig({ zoom: zoom, moveUp: next.moveUp, moveRight: next.moveRight, mode4k: mode4k }).zoom
    moveUp = next.moveUp
    moveRight = next.moveRight
  }

  function hitHandle(mx, my) {
    var c = cropPx
    var s = Style.space(18)
    function near(x, y) { return Math.abs(mx - x) <= s && Math.abs(my - y) <= s }
    if (near(c.x, c.y)) return "nw"
    if (near(c.x + c.w, c.y)) return "ne"
    if (near(c.x, c.y + c.h)) return "sw"
    if (near(c.x + c.w, c.y + c.h)) return "se"
    if (mx >= c.x && mx <= c.x + c.w && my >= c.y && my <= c.y + c.h) return "pan"
    return ""
  }

  function applyDrag(mx, my) {
    var origin = Model.previewToSource(dragOriginX, dragOriginY, paint, sourceSize.w, sourceSize.h)
    var now = Model.previewToSource(mx, my, paint, sourceSize.w, sourceSize.h)
    var dx = now.x - origin.x
    var dy = now.y - origin.y
    var start = Model.viewport(sourceSize.w, sourceSize.h, dragZoom, dragMoveUp, dragMoveRight)
    if (dragMode === "pan") {
      var next = Model.viewport(sourceSize.w, sourceSize.h, dragZoom, dragMoveUp - dy, dragMoveRight + dx)
      zoom = dragZoom
      moveUp = next.moveUp
      moveRight = next.moveRight
      return
    }
    var x = start.x
    var y = start.y
    var w = start.w
    var h = start.h
    if (dragMode === "se") { w = start.w + dx; h = start.h + dy }
    else if (dragMode === "nw") { x = start.x + dx; y = start.y + dy; w = start.w - dx; h = start.h - dy }
    else if (dragMode === "ne") { y = start.y + dy; w = start.w + dx; h = start.h - dy }
    else if (dragMode === "sw") { x = start.x + dx; w = start.w - dx; h = start.h + dy }
    var mapped = Model.fromRect(sourceSize.w, sourceSize.h, x, y, w, h)
    zoom = mapped.zoom
    moveUp = mapped.moveUp
    moveRight = mapped.moveRight
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omacam-framer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(980), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(780), panel.height - Style.gapsOut * 2)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.applyAndStart()
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.moveRight -= 8
            root.clampDraft()
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.moveRight += 8
            root.clampDraft()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.moveUp += 8
            root.clampDraft()
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.moveUp -= 8
            root.clampDraft()
            event.accepted = true
          }
        }
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: Style.spacing.md

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.md

          Text {
            text: "Omacam"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
          }

          Text {
            text: "4K source"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          ToggleSwitch {
            checked: root.mode4k
            foreground: root.foreground
            onToggled: {
              root.mode4k = !root.mode4k
              root.clampDraft()
              root.pushDraftToService()
              if (root.service) root.service.takeSnapshot()
            }
          }
        }

        Text {
          Layout.fillWidth: true
          text: root.statusLine
          color: root.foreground
          opacity: 0.75
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Item {
          id: previewStage
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true

          Rectangle {
            anchors.fill: parent
            color: "#111"
            radius: Math.max(6, root.cornerRadius - 2)
          }

          Image {
            id: previewImage
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            source: root.service ? root.service.previewUrl : ""
          }

          Text {
            anchors.centerIn: parent
            visible: previewImage.status !== Image.Ready
            text: root.service && root.service.lastError ? root.service.lastError : "Capturing preview…"
            color: "#ddd"
            font.family: root.fontFamily
            width: parent.width * 0.8
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }

          Item {
            id: cropChrome
            anchors.fill: parent
            visible: previewImage.status === Image.Ready && root.paint.w > 0

            Rectangle { x: root.paint.x; y: root.paint.y; width: root.paint.w; height: Math.max(0, root.cropPx.y - root.paint.y); color: "#99000000" }
            Rectangle { x: root.paint.x; y: root.cropPx.y + root.cropPx.h; width: root.paint.w; height: Math.max(0, root.paint.y + root.paint.h - (root.cropPx.y + root.cropPx.h)); color: "#99000000" }
            Rectangle { x: root.paint.x; y: root.cropPx.y; width: Math.max(0, root.cropPx.x - root.paint.x); height: root.cropPx.h; color: "#99000000" }
            Rectangle { x: root.cropPx.x + root.cropPx.w; y: root.cropPx.y; width: Math.max(0, root.paint.x + root.paint.w - (root.cropPx.x + root.cropPx.w)); height: root.cropPx.h; color: "#99000000" }

            Rectangle {
              x: root.cropPx.x
              y: root.cropPx.y
              width: root.cropPx.w
              height: root.cropPx.h
              color: "transparent"
              border.color: "#ffffff"
              border.width: 2
            }

            Repeater {
              model: 4
              Rectangle {
                required property int index
                width: Style.space(12)
                height: Style.space(12)
                radius: 2
                color: "#ffffff"
                x: (index % 2 === 0 ? root.cropPx.x : root.cropPx.x + root.cropPx.w) - width / 2
                y: (index < 2 ? root.cropPx.y : root.cropPx.y + root.cropPx.h) - height / 2
              }
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: {
              var mode = root.dragMode || root.hitHandle(mouseX, mouseY)
              if (mode === "pan") return Qt.SizeAllCursor
              if (mode === "nw" || mode === "se") return Qt.SizeFDiagCursor
              if (mode === "ne" || mode === "sw") return Qt.SizeBDiagCursor
              return Qt.ArrowCursor
            }
            onPressed: function(mouse) {
              var mode = root.hitHandle(mouse.x, mouse.y)
              if (!mode) return
              root.dragMode = mode
              root.dragOriginX = mouse.x
              root.dragOriginY = mouse.y
              root.dragZoom = root.zoom
              root.dragMoveUp = root.moveUp
              root.dragMoveRight = root.moveRight
            }
            onPositionChanged: function(mouse) {
              if (root.dragMode) root.applyDrag(mouse.x, mouse.y)
            }
            onReleased: root.dragMode = ""
            onWheel: function(wheel) {
              var delta = wheel.angleDelta.y > 0 ? 2 : -2
              root.zoom = Model.mergeConfig({ zoom: root.zoom + delta, mode4k: root.mode4k }).zoom
              root.clampDraft()
            }
          }
        }

        GridLayout {
          Layout.fillWidth: true
          columns: 2
          columnSpacing: Style.spacing.md
          rowSpacing: Style.spacing.sm

          Text { text: "Zoom " + root.zoom + "%"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
          PanelSlider {
            Layout.fillWidth: true
            value: root.zoom
            minimum: 0
            maximum: 80
            step: 1
            integer: true
            onMoved: function(v) { root.zoom = Math.round(v); root.clampDraft() }
          }

          Text { text: "Move right " + root.moveRight + "px"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
          PanelSlider {
            Layout.fillWidth: true
            value: root.moveRight
            minimum: -root.view.maxMoveRight
            maximum: root.view.maxMoveRight
            step: 2
            integer: true
            onMoved: function(v) { root.moveRight = Math.round(v); root.clampDraft() }
          }

          Text { text: "Move up " + root.moveUp + "px"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
          PanelSlider {
            Layout.fillWidth: true
            value: root.moveUp
            minimum: -root.view.maxMoveUp
            maximum: root.view.maxMoveUp
            step: 2
            integer: true
            onMoved: function(v) { root.moveUp = Math.round(v); root.clampDraft() }
          }
        }

        Text {
          Layout.fillWidth: true
          text: "Viewport " + root.view.w + "×" + root.view.h + " at +" + root.view.x + "," + root.view.y + "  →  1920×1080"
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.md

          Button {
            text: "Cancel"
            foreground: root.foreground
            bordered: true
            onClicked: root.dismiss()
          }

          Item { Layout.fillWidth: true }

          Button {
            text: "Start cropped camera"
            foreground: root.foreground
            active: true
            onClicked: root.applyAndStart()
          }
        }
      }
    }
  }
}
