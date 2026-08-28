import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Rclone popup dashboard shown inside the bar widget's KeyboardPanel.
// Same visual grammar as the Network / MPD / Home Assistant panels:
// a compact header, a row of text tabs, a hairline separator, and a
// fixed-height content area of thin-bordered cards on the panel fill.
Column {
  id: root
  spacing: Style.space(10)

  property QtObject bar: null
  property string pluginPath: ""
  property var status: Model.emptyStatus()
  property bool popupOpen: false

  signal runAction(string cmd, string arg1, string arg2)
  signal refreshRequested()
  signal closeRequested()

  // QML signal emission is strict about arity: emitting runAction() with
  // fewer than three arguments throws "Insufficient arguments". Route every
  // call site through this helper so optional args default to "".
  function doAction(cmd, arg1, arg2) {
    root.runAction(
      cmd,
      (arg1 === undefined || arg1 === null) ? "" : String(arg1),
      (arg2 === undefined || arg2 === null) ? "" : String(arg2))
  }

  // 0 Overview · 1 Schedules · 2 Remotes · 3 Mounts · 4 History
  property int currentTab: 0

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color muted: Qt.darker(foreground, 1.4)
  readonly property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.10)
  readonly property color track: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
  readonly property color cardFill: Style.normalFillFor(foreground, Color.accent)
  readonly property var cardBorder: Border.flat(faint, 1)

  readonly property var processes: (status && status.processes) ? status.processes : []
  // Only data-moving operations. A persistent `rclone mount` daemon is not a
  // transfer — its /proc counters tick on every VFS poll, which otherwise
  // made the Overview card and speed graph twitch a few times a minute.
  readonly property var transfers: root.processes.filter(function(p) { return p && p.is_transfer === true })
  readonly property var remotes: (status && status.remotes) ? status.remotes : []
  readonly property var mounts: (status && status.mounts) ? status.mounts : []
  readonly property var timers: (status && status.timers) ? status.timers : []
  readonly property var history: (status && status.history) ? status.history : []
  readonly property var nextTimer: (status && status.next_timer) ? status.next_timer : null
  readonly property bool installed: Boolean(status && status.installed)
  readonly property bool syncing: Boolean(status && status.is_sync_running)

  // ---- Aggregate bandwidth history ------------------------------------
  // status.py reports total_bandwidth_bps each poll (every rclone process,
  // mounts included). We keep one short rolling series and plot a single
  // line — total throughput rclone is pulling, not a plot per transfer.
  readonly property int bandwidthCapacity: 48
  property var bandwidthHistory: []
  property real bandwidthPeak: 1

  function updateBandwidthHistory() {
    var v = Math.max(0, Number(status && status.total_bandwidth_bps) || 0)
    var arr = bandwidthHistory.slice()
    arr.push(v)
    while (arr.length > bandwidthCapacity)
      arr.shift()
    var peak = 1
    for (var i = 0; i < arr.length; i++)
      if (arr[i] > peak) peak = arr[i]
    bandwidthHistory = arr
    bandwidthPeak = peak
  }

  onStatusChanged: updateBandwidthHistory()
  onPopupOpenChanged: if (popupOpen) { bandwidthHistory = []; bandwidthPeak = 1 }

  // A thin-bordered card sitting on the panel fill. Self-contained so it
  // stays valid as an inline component; callers set size and children.
  component Card: BorderSurface {
    width: parent ? parent.width : 0
    radius: Style.cornerRadius
    color: Style.normalFillFor(Color.foreground, Color.accent)
    borderSpec: Border.flat(Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10), 1)
  }

  component Pill: BorderSurface {
    property string label: ""
    property color labelColor: Qt.darker(Color.foreground, 1.4)
    implicitWidth: pillText.implicitWidth + Style.space(12)
    implicitHeight: Style.space(16)
    radius: Style.cornerRadius
    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10)
    borderSpec: Border.none()
    Text {
      id: pillText
      anchors.centerIn: parent
      text: parent.label
      color: parent.labelColor
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  component MetaLine: Text {
    color: Qt.darker(Color.foreground, 1.4)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
    width: parent ? parent.width : 0
  }

  // Single-line area chart of total rclone throughput. `points` is the
  // rolling [bps, ...] buffer, newest last, right-aligned to the edge.
  component BandwidthGraph: Item {
    id: graph
    property var points: []
    property real peak: 1
    property int capacity: 48
    implicitHeight: Style.space(44)

    readonly property var _xy: {
      var pts = graph.points || []
      var n = pts.length
      var w = graph.width
      var h = graph.height
      var denom = Math.max(1, graph.capacity - 1)
      var scale = graph.peak > 0 ? graph.peak : 1
      var line = []
      for (var i = 0; i < n; i++) {
        var x = w - (n - 1 - i) / denom * w
        var frac = Math.max(0, Math.min(1, pts[i] / scale))
        line.push(Qt.point(x, h - 1.5 - frac * (h - 3)))
      }
      return line
    }

    Rectangle {   // baseline
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
    }

    Rectangle {   // midline
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: 1
      color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
    }

    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      visible: graph._xy.length >= 2

      // Filled area under the curve.
      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillColor: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
        PathPolyline {
          path: {
            var line = graph._xy
            if (line.length < 2) return []
            var poly = line.slice()
            poly.push(Qt.point(line[line.length - 1].x, graph.height))
            poly.push(Qt.point(line[0].x, graph.height))
            return poly
          }
        }
      }

      // The line itself.
      ShapePath {
        strokeColor: Color.accent
        strokeWidth: 1
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathPolyline { path: graph._xy }
      }
    }
  }

  // =========================================================================
  // 1. Header
  // =========================================================================
  Item {
    id: header
    width: parent.width
    height: Math.max(iconBox.height, titleCol.implicitHeight)

    BorderSurface {
      id: iconBox
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(34)
      height: Style.space(34)
      radius: Style.cornerRadius
      color: root.syncing ? Style.selectedFillFor(root.foreground, Color.accent)
                          : Style.normalFillFor(root.foreground, Color.accent)
      borderSpec: root.cardBorder

      Text {
        anchors.centerIn: parent
        text: root.syncing ? "󰑮" : "󰅟"
        color: root.syncing ? Color.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }
    }

    Column {
      id: titleCol
      anchors.left: iconBox.right
      anchors.leftMargin: Style.space(10)
      anchors.right: headerActions.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Row {
        spacing: Style.space(6)

        Text {
          text: "Rclone"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        // Sync LED: pulsing accent while a transfer runs, dim when idle,
        // urgent when rclone is missing.
        Rectangle {
          id: syncLed
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(7)
          height: Style.space(7)
          radius: width / 2
          color: !root.installed ? Color.urgent
                 : root.syncing ? Color.accent
                 : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)

          SequentialAnimation {
            id: syncLedPulse
            running: root.syncing
            loops: Animation.Infinite
            onRunningChanged: if (!running) syncLed.opacity = 1.0
            NumberAnimation { target: syncLed; property: "opacity"; from: 1.0; to: 0.3; duration: 720; easing.type: Easing.InOutSine }
            NumberAnimation { target: syncLed; property: "opacity"; from: 0.3; to: 1.0; duration: 720; easing.type: Easing.InOutSine }
          }
        }
      }

      Text {
        width: parent.width
        text: !root.installed ? "Not found on PATH"
              : root.syncing ? Model.barTooltipText(root.status).replace("Rclone: ", "")
              : root.nextTimer && root.nextTimer.next_formatted ? "Next " + root.nextTimer.profile + " " + root.nextTimer.next_formatted
              : root.remotes.length + " remote" + (root.remotes.length === 1 ? "" : "s") + " · " + root.mounts.length + " mount" + (root.mounts.length === 1 ? "" : "s")
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Row {
      id: headerActions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Button {
        iconText: "󰑐"
        iconSize: Style.font.body
        foreground: root.foreground
        horizontalPadding: Style.space(7)
        verticalPadding: Style.space(5)
        tooltipText: "Refresh"
        onClicked: root.refreshRequested()
      }
      Button {
        iconText: "󰅖"
        iconSize: Style.font.body
        foreground: root.foreground
        horizontalPadding: Style.space(7)
        verticalPadding: Style.space(5)
        tooltipText: "Close"
        onClicked: root.closeRequested()
      }
    }
  }

  // =========================================================================
  // 2. Tabs
  // =========================================================================
  Row {
    width: parent.width
    spacing: Style.space(4)

    Repeater {
      model: ["Overview", "Schedules", "Remotes", "Mounts", "History"]
      delegate: Button {
        required property int index
        required property string modelData
        text: modelData
        fontSize: Style.font.caption
        foreground: root.foreground
        bordered: true
        selected: root.currentTab === index
        horizontalPadding: Style.space(7)
        verticalPadding: Style.space(3)
        onClicked: root.currentTab = index
      }
    }
  }

  PanelSeparator { foreground: root.foreground }

  // =========================================================================
  // 3. Content
  // =========================================================================
  Item {
    width: parent.width
    height: Style.space(300)

    Text {
      anchors.centerIn: parent
      visible: !root.installed
      text: "Install rclone to use this panel."
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    // ------------------------------------------------------------- Overview
    Flickable {
      anchors.fill: parent
      visible: root.installed && root.currentTab === 0
      contentHeight: overviewCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: overviewCol
        width: parent.width
        spacing: Style.space(8)

        // Total rclone bandwidth (transfers + mounts streaming files)
        Card {
          visible: root.transfers.length > 0 || root.mounts.length > 0
          implicitHeight: bwCol.implicitHeight + Style.space(20)
          Column {
            id: bwCol
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(6)

            Item {
              width: parent.width
              height: bwLabel.implicitHeight
              Text {
                id: bwLabel
                anchors.left: parent.left
                text: "Bandwidth"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
              Text {
                anchors.right: parent.right
                anchors.baseline: bwLabel.baseline
                text: Model.formatRate(root.status && root.status.total_bandwidth_bps ? root.status.total_bandwidth_bps : 0)
                      + "  ·  peak " + Model.formatRate(root.bandwidthPeak)
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            BandwidthGraph {
              width: parent.width
              points: root.bandwidthHistory
              peak: root.bandwidthPeak
              capacity: root.bandwidthCapacity
            }

            MetaLine {
              text: {
                var parts = []
                if (root.transfers.length > 0)
                  parts.push(root.transfers.length + " transfer" + (root.transfers.length === 1 ? "" : "s") + " running")
                if (root.mounts.length > 0)
                  parts.push(root.mounts.length + " mount" + (root.mounts.length === 1 ? "" : "s"))
                return parts.join("  ·  ")
              }
            }
          }
        }

        // Mounts present on this system (full controls on the Mounts tab)
        Card {
          visible: root.mounts.length > 0
          implicitHeight: mountsMiniCol.implicitHeight + Style.space(20)
          Column {
            id: mountsMiniCol
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(6)

            Text {
              text: "Mounts (" + root.mounts.length + ")"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.currentTab = 3
              }
            }

            Repeater {
              model: root.mounts
              delegate: Row {
                required property var modelData
                width: parent.width
                spacing: Style.space(6)
                Text {
                  text: "󱂵"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  width: parent.width - parent.spacing - Style.space(12)
                  text: (modelData.source ? modelData.source : modelData.remote) + "  →  " + modelData.target
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                }
              }
            }
          }
        }

        // Next scheduled job
        Card {
          visible: Boolean(root.nextTimer)
          implicitHeight: nextCol.implicitHeight + Style.space(20)
          Row {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(10)

            Column {
              id: nextCol
              width: parent.width - runNowBtn.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Item {
                width: parent.width
                height: nextName.implicitHeight

                Text {
                  id: nextName
                  anchors.left: parent.left
                  anchors.right: nextTags.left
                  anchors.rightMargin: Style.space(6)
                  text: "Next: " + (root.nextTimer ? root.nextTimer.profile : "")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  elide: Text.ElideRight
                }
                Row {
                  id: nextTags
                  anchors.right: parent.right
                  anchors.verticalCenter: nextName.verticalCenter
                  spacing: Style.space(4)
                  Pill {
                    label: root.nextTimer ? root.nextTimer.next_formatted : ""
                    labelColor: Color.accent
                  }
                  Pill {
                    label: root.nextTimer ? Model.syncKindLabel(root.nextTimer.sync_type) : ""
                  }
                }
              }

              MetaLine {
                visible: Boolean(root.nextTimer && root.nextTimer.local_path)
                text: "󰉋 " + (root.nextTimer ? root.nextTimer.local_path : "") + "  →  󰅟 " + (root.nextTimer ? root.nextTimer.remote_path : "")
              }
              MetaLine {
                text: "last run " + (root.nextTimer ? root.nextTimer.last_formatted : "n/a")
              }
            }

            Button {
              id: runNowBtn
              anchors.verticalCenter: parent.verticalCenter
              text: "Sync now"
              iconText: "󰐊"
              fontSize: Style.font.caption
              iconSize: Style.font.caption
              foreground: root.foreground
              bordered: true
              onClicked: {
                if (root.nextTimer)
                  root.doAction("sync", root.nextTimer.service_unit || root.nextTimer.profile)
              }
            }
          }
        }

        Text {
          visible: root.remotes.length > 0
          text: "Storage"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Repeater {
          model: root.remotes
          delegate: Card {
            required property var modelData
            implicitHeight: quotaCol.implicitHeight + Style.space(20)
            Column {
              id: quotaCol
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(6)

              Row {
                width: parent.width
                spacing: Style.space(6)
                Text {
                  text: modelData.icon
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  width: parent.width - parent.spacing * 2 - pctText.width - 20
                  text: modelData.name + "  ·  " + modelData.provider
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  id: pctText
                  visible: modelData.has_quota
                  text: Model.formatPercent(modelData.used_percent) + "%"
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Rectangle {
                visible: modelData.has_quota
                width: parent.width
                height: Style.space(4)
                radius: height / 2
                color: root.track
                Rectangle {
                  width: parent.width * (Model.formatPercent(modelData.used_percent) / 100)
                  height: parent.height
                  radius: height / 2
                  color: Color.accent
                }
              }

              MetaLine {
                text: modelData.has_quota
                  ? "used " + modelData.used_formatted + " · free " + modelData.free_formatted + " · total " + modelData.total_formatted
                  : "quota not reported by this remote"
              }
            }
          }
        }
      }
    }

    // ------------------------------------------------------------- Schedules
    Flickable {
      anchors.fill: parent
      visible: root.installed && root.currentTab === 1
      contentHeight: schedCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: schedCol
        width: parent.width
        spacing: Style.space(8)

        // 24-hour timeline
        Card {
          implicitHeight: tlCol.implicitHeight + Style.space(20)
          Column {
            id: tlCol
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(6)

            Text {
              text: "Next 24 hours"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Item {
              id: ruler
              width: parent.width
              height: Style.space(26)

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: Style.space(6)
                height: 1
                color: root.faint
              }

              Repeater {
                model: [0, 6, 12, 18, 24]
                delegate: Text {
                  required property int modelData
                  x: Math.min(ruler.width - width, Math.max(0, Model.calculateTimelineX(modelData, ruler.width) - width / 2))
                  anchors.bottom: parent.bottom
                  text: (modelData < 10 ? "0" : "") + modelData + ":00"
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption - 1
                }
              }

              Repeater {
                model: root.timers
                delegate: Rectangle {
                  required property var modelData
                  visible: modelData.next_hour >= 0
                  x: Math.min(ruler.width - width, Math.max(0, Model.calculateTimelineX(modelData.next_hour, ruler.width) - width / 2))
                  y: Style.space(3)
                  width: Style.space(7)
                  height: Style.space(7)
                  radius: width / 2
                  color: Color.accent
                }
              }
            }
          }
        }

        Text {
          text: "Timers (" + root.timers.length + ")"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          visible: root.timers.length === 0
          text: "No rclone systemd timers or cron entries found."
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: root.timers
          delegate: Card {
            required property var modelData
            implicitHeight: timerRow.implicitHeight + Style.space(20)
            Row {
              id: timerRow
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(10)

              Column {
                width: parent.width - runTimerBtn.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Item {
                  width: parent.width
                  height: timerName.implicitHeight

                  Text {
                    id: timerName
                    anchors.left: parent.left
                    anchors.right: timerTags.left
                    anchors.rightMargin: Style.space(6)
                    text: (modelData.is_running ? "󰑮  " : "") + modelData.profile
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  Row {
                    id: timerTags
                    anchors.right: parent.right
                    anchors.verticalCenter: timerName.verticalCenter
                    spacing: Style.space(4)
                    Pill {
                      label: Model.syncKindLabel(modelData.sync_type)
                      labelColor: Color.accent
                    }
                    Pill { label: modelData.scope }
                  }
                }

                MetaLine {
                  visible: Boolean(modelData.local_path)
                  text: "󰉋 " + modelData.local_path + (modelData.remote_path ? ("  →  󰅟 " + modelData.remote_path) : "")
                }
                MetaLine {
                  text: "next " + modelData.next_formatted + " · last " + modelData.last_formatted
                }
              }

              Button {
                id: runTimerBtn
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰐊"
                iconSize: Style.font.caption
                foreground: root.foreground
                bordered: true
                horizontalPadding: Style.space(7)
                verticalPadding: Style.space(5)
                tooltipText: "Run now"
                onClicked: root.doAction("sync", modelData.service_unit || modelData.profile)
              }
            }
          }
        }
      }
    }

    // ------------------------------------------------------------- Remotes
    Flickable {
      anchors.fill: parent
      visible: root.installed && root.currentTab === 2
      contentHeight: remotesCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: remotesCol
        width: parent.width
        spacing: Style.space(8)

        Text {
          visible: root.remotes.length === 0
          text: "No remotes configured (rclone config)."
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: root.remotes
          delegate: Card {
            required property var modelData
            implicitHeight: remoteCol.implicitHeight + Style.space(20)
            Column {
              id: remoteCol
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(6)

              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  text: modelData.icon
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.iconLarge
                }
                Column {
                  width: parent.width - parent.spacing - 24
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(1)
                  Text {
                    text: modelData.name + ":"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                  MetaLine { text: modelData.provider + " (" + modelData.type + ")" }
                }
              }

              Rectangle {
                visible: modelData.has_quota
                width: parent.width
                height: Style.space(5)
                radius: height / 2
                color: root.track
                Rectangle {
                  width: parent.width * (Model.formatPercent(modelData.used_percent) / 100)
                  height: parent.height
                  radius: height / 2
                  color: Color.accent
                }
              }

              MetaLine {
                visible: modelData.has_quota
                text: "used " + modelData.used_formatted + " · free " + modelData.free_formatted
                  + " · total " + modelData.total_formatted
                  + (modelData.trash_formatted && modelData.trash_formatted !== "0 B" ? (" · trash " + modelData.trash_formatted) : "")
              }
              MetaLine {
                visible: !modelData.has_quota
                text: "quota not reported by this remote"
              }
            }
          }
        }
      }
    }

    // ------------------------------------------------------------- Mounts
    Flickable {
      anchors.fill: parent
      visible: root.installed && root.currentTab === 3
      contentHeight: mountsCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: mountsCol
        width: parent.width
        spacing: Style.space(8)

        Text {
          visible: root.mounts.length === 0
          text: "No active rclone FUSE mounts."
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: root.mounts
          delegate: Card {
            required property var modelData
            implicitHeight: mountRow.implicitHeight + Style.space(20)
            Row {
              id: mountRow
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              Column {
                width: parent.width - mountActions.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Item {
                  width: parent.width
                  height: mountTarget.implicitHeight

                  Text {
                    id: mountTarget
                    anchors.left: parent.left
                    anchors.right: mountTag.left
                    anchors.rightMargin: Style.space(6)
                    text: "󱂵  " + modelData.target
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideMiddle
                  }
                  Pill {
                    id: mountTag
                    anchors.right: parent.right
                    anchors.verticalCenter: mountTarget.verticalCenter
                    label: {
                      var o = String(modelData.options || "").split(",")[0]
                      return (o === "rw" || o === "ro") ? o : "fuse"
                    }
                    labelColor: Color.accent
                  }
                }
                MetaLine { text: modelData.source }
              }

              Row {
                id: mountActions
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)
                Button {
                  iconText: "󰝰"
                  iconSize: Style.font.caption
                  foreground: root.foreground
                  bordered: true
                  horizontalPadding: Style.space(7)
                  verticalPadding: Style.space(5)
                  tooltipText: "Open folder"
                  onClicked: root.doAction("open_folder", modelData.target)
                }
                Button {
                  text: "Unmount"
                  fontSize: Style.font.caption
                  foreground: root.foreground
                  bordered: true
                  horizontalPadding: Style.space(7)
                  verticalPadding: Style.space(4)
                  onClicked: root.doAction("unmount", modelData.target)
                }
              }
            }
          }
        }
      }
    }

    // ------------------------------------------------------------- History
    Flickable {
      anchors.fill: parent
      visible: root.installed && root.currentTab === 4
      contentHeight: historyCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: historyCol
        width: parent.width
        spacing: Style.space(4)

        Text {
          visible: root.history.length === 0
          text: "No recent runs in the systemd journal."
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: root.history
          delegate: Card {
            required property var modelData
            implicitHeight: Style.space(30)
            Item {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)

              Text {
                id: histIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.status === "success" ? "󰄬" : "󰅚"
                color: modelData.status === "success" ? Color.accent : Color.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                id: histProfile
                anchors.left: histIcon.right
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.profile
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                id: histTime
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.time
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                anchors.left: histProfile.right
                anchors.leftMargin: Style.space(8)
                anchors.right: histTime.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.message
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }
        }
      }
    }
  }
}
