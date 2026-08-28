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
  // Remote quota (`rclone about`) hits the provider API, so it is cached
  // between polls. Manual Refresh forces a fresh read.
  readonly property int quotaTtlSec: Math.max(60, Number(setting("quotaRefreshMinutes", 15)) * 60)

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

  function refreshStatus(forceQuota) {
    if (statusProc.running) return
    var ttl = forceQuota === true ? 0 : root.quotaTtlSec
    statusProc.command = ["bash", root.pluginPath + "/scripts/status.sh", "--quota-ttl", String(ttl)]
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
      if (b === Qt.MiddleButton) root.refreshStatus(true)
      else root.toggle()
    }

    // Sync LED: a small pulsing dot in the corner of the bar icon while a
    // transfer is actively running, so it reads at a glance without opening
    // the panel. Ringed in the bar background so it stays legible on the glyph.
    Rectangle {
      id: syncLed
      visible: root.isSyncRunning
      width: Style.space(6)
      height: Style.space(6)
      radius: width / 2
      z: 5
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: Style.space(3)
      anchors.topMargin: Style.space(3)
      color: Color.accent
      border.width: 1
      border.color: Color.bar.background

      SequentialAnimation {
        running: syncLed.visible
        loops: Animation.Infinite
        onRunningChanged: if (!running) syncLed.opacity = 1.0
        NumberAnimation { target: syncLed; property: "opacity"; from: 1.0; to: 0.3; duration: 720; easing.type: Easing.InOutSine }
        NumberAnimation { target: syncLed; property: "opacity"; from: 0.3; to: 1.0; duration: 720; easing.type: Easing.InOutSine }
      }
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
      onRefreshRequested: root.refreshStatus(true)
      onCloseRequested: root.close()
    }
  }
}
