import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "susamn.rclone"
  ipcTarget: "susamn.rclone"

  readonly property string pluginPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/susamn.rclone"
  readonly property int closedIntervalMs: Math.max(2000, Number(setting("pollIntervalClosedSec", 10)) * 1000)
  readonly property int openIntervalMs: Math.max(1000, Number(setting("pollIntervalOpenSec", 2)) * 1000)

  property var status: Model.emptyStatus()
  readonly property bool isSyncRunning: Boolean(status && status.is_sync_running)
  readonly property string icon: isSyncRunning ? "󰑮" : "󰅟"

  function runAction(cmd, arg1, arg2) {
    var args = ["bash", root.pluginPath + "/scripts/action.sh", cmd]
    if (arg1 !== undefined && arg1 !== null && String(arg1).length > 0) args.push(String(arg1))
    if (arg2 !== undefined && arg2 !== null && String(arg2).length > 0) args.push(String(arg2))
    Quickshell.execDetached(args)
    actionRefreshTimer.restart()
  }

  function refreshStatus() {
    if (statusProc.running) return
    statusProc.command = ["bash", root.pluginPath + "/scripts/status.sh"]
    statusProc.running = true
  }

  function applyStatus(text) {
    var parsed = Model.parseJson(text, null)
    if (!parsed) return
    root.status = parsed
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refreshStatus()

  onOpenedChanged: {
    if (root.opened) {
      root.refreshStatus()
    }
  }

  Timer {
    id: actionRefreshTimer
    interval: 300
    repeat: false
    onTriggered: root.refreshStatus()
  }

  Timer {
    interval: root.opened ? root.openIntervalMs : root.closedIntervalMs
    repeat: true
    running: true
    onTriggered: root.refreshStatus()
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    tooltipText: Model.barTooltipText(root.status)
    active: root.isSyncRunning

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refreshStatus()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(dashboard.implicitHeight)

    RcloneDashboard {
      id: dashboard
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      bar: root.bar
      pluginPath: root.pluginPath
      status: root.status
      popupOpen: root.opened
      onRunAction: function(cmd, arg1, arg2) { root.runAction(cmd, arg1, arg2) }
      onRefreshRequested: root.refreshStatus()
      onCloseRequested: root.close()
    }
  }
}
