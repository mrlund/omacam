import QtQuick
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "mrlund.omacam"

  readonly property var cam: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property bool live: cam ? cam.running === true : false
  readonly property bool busy: cam ? cam.busy === true : false
  readonly property string err: cam ? String(cam.lastError || "") : ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function openFramer() {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.summon !== "function") return
    root.bar.shell.summon(root.moduleName, "{}")
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.live ? "󰄀" : "󰖠"
    active: root.live
    tooltipText: root.err
      ? ("Omacam: " + root.err)
      : (root.live
        ? "Omacam is live — click to stop, right-click to reframe"
        : "Omacam — click to start, right-click to frame the crop")
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.openFramer()
        return
      }
      if (b === Qt.MiddleButton) {
        if (root.cam && root.cam.running) root.cam.stop()
        return
      }
      if (!root.cam || root.busy) return
      root.cam.toggle()
    }
  }
}
