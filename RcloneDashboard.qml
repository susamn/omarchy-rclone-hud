import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var bar: null
  property string pluginPath: ""
  property var status: Model.emptyStatus()
  property bool popupOpen: false

  signal runAction(string cmd, string arg1, string arg2)
  signal closeRequested()

  property int currentTab: 0 // 0: Overview, 1: Schedules, 2: Remotes, 3: Mounts, 4: History

  readonly property var processes: (status && status.processes) ? status.processes : []
  readonly property var remotes: (status && status.remotes) ? status.remotes : []
  readonly property var mounts: (status && status.mounts) ? status.mounts : []
  readonly property var timers: (status && status.timers) ? status.timers : []
  readonly property var history: (status && status.history) ? status.history : []
  readonly property var nextTimer: (status && status.next_timer) ? status.next_timer : null

  readonly property color fg: Color.menu.text
  readonly property color bg: Color.menu.background
  readonly property color borderCol: Color.menu.border
  readonly property color accentCol: Color.accent
  readonly property color mutedCol: Color.muted
  readonly property color brightCol: Util.alpha(Color.foreground, 0.08)

  implicitWidth: Style.space(700)
  implicitHeight: contentColumn.implicitHeight + Style.space(24)

  ColumnLayout {
    id: contentColumn
    anchors.fill: parent
    anchors.margins: Style.space(14)
    spacing: Style.space(12)

    // ------------------------------------------------------------- Header
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(10)

      Rectangle {
        width: Style.space(32)
        height: Style.space(32)
        radius: Style.cornerRadius
        color: status && status.is_sync_running ? root.accentCol : root.brightCol

        Text {
          anchors.centerIn: parent
          text: status && status.is_sync_running ? "󰑮" : "󰜱"
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          color: status && status.is_sync_running ? Color.background : root.fg
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)

        Text {
          text: "Rclone Cloud & Sync"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
          color: root.fg
        }

        RowLayout {
          spacing: Style.space(6)

          // Running badge
          Rectangle {
            visible: Boolean(status && status.is_sync_running)
            height: Style.space(18)
            width: runningText.implicitWidth + Style.space(12)
            radius: Style.space(9)
            color: root.accentCol

            Text {
              id: runningText
              anchors.centerIn: parent
              text: "● Syncing"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.weight: Font.Bold
              color: Color.background
            }
          }

          // Next Run Badge
          Rectangle {
            visible: Boolean(nextTimer && nextTimer.next_formatted)
            height: Style.space(18)
            width: nextText.implicitWidth + Style.space(12)
            radius: Style.space(9)
            color: root.brightCol

            Text {
              id: nextText
              anchors.centerIn: parent
              text: "Next: " + (nextTimer ? nextTimer.next_formatted : "")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: root.mutedCol
            }
          }

          // Remotes Badge
          Rectangle {
            height: Style.space(18)
            width: remotesBadgeText.implicitWidth + Style.space(12)
            radius: Style.space(9)
            color: root.brightCol

            Text {
              id: remotesBadgeText
              anchors.centerIn: parent
              text: (remotes.length) + " Remote" + (remotes.length === 1 ? "" : "s")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: root.mutedCol
            }
          }
        }
      }

      // Refresh Button
      Rectangle {
        width: Style.space(28)
        height: Style.space(28)
        radius: Style.cornerRadius
        color: refreshMouse.containsMouse ? root.brightCol : "transparent"
        border.width: 1
        border.color: root.borderCol

        Text {
          anchors.centerIn: parent
          text: "󰑐"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: root.fg
        }

        MouseArea {
          id: refreshMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.runAction("refresh")
        }
      }

      // Close Button
      Rectangle {
        width: Style.space(28)
        height: Style.space(28)
        radius: Style.cornerRadius
        color: closeMouse.containsMouse ? root.brightCol : "transparent"
        border.width: 1
        border.color: root.borderCol

        Text {
          anchors.centerIn: parent
          text: "󰅖"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: root.fg
        }

        MouseArea {
          id: closeMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.closeRequested()
        }
      }
    }

    // ------------------------------------------------------------- Tab Bar
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(6)

      Repeater {
        model: [
          { name: "Overview", icon: "󰄬" },
          { name: "Schedules", icon: "󱡶" },
          { name: "Remotes", icon: "󰅟" },
          { name: "Mounts", icon: "󰉍" },
          { name: "History", icon: "󰋚" }
        ]

        delegate: Rectangle {
          id: tabBtn
          readonly property bool isSelected: root.currentTab === index
          Layout.fillWidth: true
          height: Style.space(30)
          radius: Style.cornerRadius
          color: isSelected ? root.accentCol : (tabArea.containsMouse ? root.brightCol : root.bg)
          border.width: 1
          border.color: isSelected ? root.accentCol : root.borderCol

          RowLayout {
            anchors.centerIn: parent
            spacing: Style.space(6)

            Text {
              text: modelData.icon
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              color: isSelected ? Color.background : root.fg
            }

            Text {
              text: modelData.name
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.weight: isSelected ? Font.DemiBold : Font.Normal
              color: isSelected ? Color.background : root.fg
            }
          }

          MouseArea {
            id: tabArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.currentTab = index
          }
        }
      }
    }

    // ------------------------------------------------------------- Tab Views Container
    Item {
      Layout.fillWidth: true
      implicitHeight: Style.space(380)

      // =========================================================== TAB 0: OVERVIEW
      Flickable {
        anchors.fill: parent
        visible: root.currentTab === 0
        contentHeight: overviewCol.implicitHeight
        clip: true

        ColumnLayout {
          id: overviewCol
          width: parent.width
          spacing: Style.space(12)

          // 1. Live Running Sync Card (if active)
          Rectangle {
            visible: Boolean(status && status.is_sync_running)
            Layout.fillWidth: true
            implicitHeight: liveSyncCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: root.bg
            border.width: 1
            border.color: root.accentCol

            ColumnLayout {
              id: liveSyncCol
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(6)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)

                Text {
                  text: "⚡ ACTIVE SYNC IN PROGRESS"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.weight: Font.Bold
                  color: root.accentCol
                }

                Item { Layout.fillWidth: true }

                Text {
                  text: processes.length > 0 ? ("PID " + processes[0].pid + " · " + processes[0].elapsed) : ""
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: root.mutedCol
                }
              }

              Repeater {
                model: processes
                delegate: ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(2)

                  Text {
                    text: modelData.command_preview
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.weight: Font.DemiBold
                    color: root.fg
                    elide: Text.ElideMiddle
                  }

                  Text {
                    visible: Boolean(modelData.flags)
                    text: "Flags: " + modelData.flags
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: root.mutedCol
                  }
                }
              }
            }
          }

          // 2. Next Scheduled Job Card
          Rectangle {
            visible: Boolean(nextTimer)
            Layout.fillWidth: true
            implicitHeight: nextTimerCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: root.bg
            border.width: 1
            border.color: root.borderCol

            RowLayout {
              id: nextTimerCol
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(12)

              Rectangle {
                width: Style.space(36)
                height: Style.space(36)
                radius: Style.cornerRadius
                color: root.brightCol

                Text {
                  anchors.centerIn: parent
                  text: "⏱️"
                  font.pixelSize: Style.font.heading
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(2)

                RowLayout {
                  spacing: Style.space(6)
                  Text {
                    text: "Next Scheduled Sync: " + (nextTimer ? nextTimer.profile : "")
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.weight: Font.DemiBold
                    color: root.fg
                  }

                  Rectangle {
                    height: Style.space(16)
                    width: countdownTxt.implicitWidth + Style.space(8)
                    radius: Style.space(8)
                    color: root.accentCol

                    Text {
                      id: countdownTxt
                      anchors.centerIn: parent
                      text: nextTimer ? nextTimer.next_formatted : ""
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.weight: Font.Bold
                      color: Color.background
                    }
                  }
                }

                Text {
                  visible: Boolean(nextTimer && nextTimer.local_path)
                  text: "📁 " + (nextTimer ? nextTimer.local_path : "") + " ➔ ☁️ " + (nextTimer ? nextTimer.remote_path : "")
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: root.mutedCol
                  elide: Text.ElideMiddle
                }

                Text {
                  text: "Service: " + (nextTimer ? nextTimer.service_unit : "") + " · Last run: " + (nextTimer ? nextTimer.last_formatted : "N/A")
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: root.mutedCol
                }
              }

              // Run Now Button
              Rectangle {
                implicitHeight: Style.space(30)
                implicitWidth: runTxt.implicitWidth + Style.space(20)
                radius: Style.cornerRadius
                color: runMouse.containsMouse ? root.accentCol : root.brightCol
                border.width: 1
                border.color: root.borderCol

                RowLayout {
                  anchors.centerIn: parent
                  spacing: Style.space(4)
                  Text {
                    text: "󰐊"
                    font.family: Style.font.family
                    color: runMouse.containsMouse ? Color.background : root.fg
                  }
                  Text {
                    id: runTxt
                    text: "Sync Now"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.weight: Font.DemiBold
                    color: runMouse.containsMouse ? Color.background : root.fg
                  }
                }

                MouseArea {
                  id: runMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (nextTimer) {
                      root.runAction("sync", nextTimer.service_unit || nextTimer.profile)
                    }
                  }
                }
              }
            }
          }

          // 3. Storage Quota Quick Overview
          Text {
            text: "Storage Capacity"
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.DemiBold
            color: root.mutedCol
          }

          Repeater {
            model: remotes
            delegate: Rectangle {
              Layout.fillWidth: true
              implicitHeight: quotaInner.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: root.bg
              border.width: 1
              border.color: root.borderCol

              ColumnLayout {
                id: quotaInner
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(6)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Text {
                    text: modelData.icon
                    font.family: Style.font.family
                    font.pixelSize: Style.font.heading
                    color: root.accentCol
                  }

                  Text {
                    text: modelData.name + " (" + modelData.provider + ")"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.weight: Font.DemiBold
                    color: root.fg
                  }

                  Item { Layout.fillWidth: true }

                  Text {
                    text: modelData.used_percent + "% Used"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.weight: Font.Bold
                    color: root.accentCol
                  }
                }

                // Progress Bar
                Rectangle {
                  Layout.fillWidth: true
                  height: Style.space(6)
                  radius: Style.space(3)
                  color: root.brightCol

                  Rectangle {
                    height: parent.height
                    width: parent.width * (Math.min(100, Math.max(0, modelData.used_percent)) / 100.0)
                    radius: Style.space(3)
                    color: root.accentCol
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  Text {
                    text: "Used: " + modelData.used_formatted + "  ·  Free: " + modelData.free_formatted + "  ·  Total: " + modelData.total_formatted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: root.mutedCol
                  }
                }
              }
            }
          }
        }
      }

      // =========================================================== TAB 1: SCHEDULES & TIMELINE
      Flickable {
        anchors.fill: parent
        visible: root.currentTab === 1
        contentHeight: schedulesCol.implicitHeight
        clip: true

        ColumnLayout {
          id: schedulesCol
          width: parent.width
          spacing: Style.space(12)

          // 24-Hour Timeline Visualizer Card
          Rectangle {
            Layout.fillWidth: true
            implicitHeight: timelineCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: root.bg
            border.width: 1
            border.color: root.borderCol

            ColumnLayout {
              id: timelineCol
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              RowLayout {
                Layout.fillWidth: true
                Text {
                  text: "24-Hour Projected Schedule Timeline"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.weight: Font.DemiBold
                  color: root.fg
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: "00:00 ➔ 24:00"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: root.mutedCol
                }
              }

              // Timeline ruler container
              Rectangle {
                id: rulerBox
                Layout.fillWidth: true
                height: Style.space(36)
                radius: Style.cornerRadius
                color: root.brightCol

                // Grid lines at 0h, 6h, 12h, 18h, 24h
                Repeater {
                  model: [0, 6, 12, 18, 24]
                  delegate: Item {
                    x: (modelData / 24.0) * (rulerBox.width - Style.space(20)) + Style.space(10)
                    height: rulerBox.height
                    width: 1

                    Rectangle {
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: Style.space(14)
                      width: 1
                      color: root.borderCol
                    }

                    Text {
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: Style.space(2)
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: (modelData < 10 ? "0" + modelData : modelData) + ":00"
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption - 1
                      color: root.mutedCol
                    }
                  }
                }

                // Timer markers on the ruler
                Repeater {
                  model: timers
                  delegate: Rectangle {
                    visible: modelData.next_hour >= 0
                    x: Math.max(0, Math.min(rulerBox.width - Style.space(12), (modelData.next_hour / 24.0) * (rulerBox.width - Style.space(20)) + Style.space(4)))
                    y: Style.space(4)
                    width: Style.space(12)
                    height: Style.space(16)
                    radius: Style.space(3)
                    color: root.accentCol

                    Text {
                      anchors.centerIn: parent
                      text: "󰑮"
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption - 1
                      color: Color.background
                    }
                  }
                }
              }
            }
          }

          // Timer List
          Text {
            text: "Configured Timers & Jobs (" + timers.length + ")"
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.DemiBold
            color: root.mutedCol
          }

          Repeater {
            model: timers
            delegate: Rectangle {
              Layout.fillWidth: true
              implicitHeight: timerItemCol.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: root.bg
              border.width: 1
              border.color: root.borderCol

              RowLayout {
                id: timerItemCol
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(10)

                Rectangle {
                  width: Style.space(32)
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  color: root.brightCol

                  Text {
                    anchors.centerIn: parent
                    text: modelData.is_running ? "󰑮" : "󱡶"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    color: modelData.is_running ? root.accentCol : root.fg
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(2)

                  RowLayout {
                    spacing: Style.space(6)
                    Text {
                      text: modelData.profile
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.weight: Font.DemiBold
                      color: root.fg
                    }

                    Rectangle {
                      height: Style.space(16)
                      width: scopeTxt.implicitWidth + Style.space(8)
                      radius: Style.space(8)
                      color: root.brightCol

                      Text {
                        id: scopeTxt
                        anchors.centerIn: parent
                        text: modelData.scope
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption - 1
                        color: root.mutedCol
                      }
                    }
                  }

                  Text {
                    visible: Boolean(modelData.local_path)
                    text: "📁 " + modelData.local_path + (modelData.remote_path ? (" ➔ ☁️ " + modelData.remote_path) : "")
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: root.mutedCol
                    elide: Text.ElideMiddle
                  }

                  Text {
                    text: "Next: " + modelData.next_formatted + "  ·  Last: " + modelData.last_formatted + "  ·  Unit: " + modelData.timer_unit
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: root.mutedCol
                  }
                }

                Rectangle {
                  implicitHeight: Style.space(28)
                  implicitWidth: Style.space(28)
                  radius: Style.cornerRadius
                  color: runTimerMouse.containsMouse ? root.accentCol : root.brightCol
                  border.width: 1
                  border.color: root.borderCol

                  Text {
                    anchors.centerIn: parent
                    text: "󰐊"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: runTimerMouse.containsMouse ? Color.background : root.fg
                  }

                  MouseArea {
                    id: runTimerMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runAction("sync", modelData.service_unit || modelData.profile)
                  }
                }
              }
            }
          }
        }
      }

      // =========================================================== TAB 2: REMOTES & STORAGE
      Flickable {
        anchors.fill: parent
        visible: root.currentTab === 2
        contentHeight: remotesCol.implicitHeight
        clip: true

        ColumnLayout {
          id: remotesCol
          width: parent.width
          spacing: Style.space(10)

          Repeater {
            model: remotes
            delegate: Rectangle {
              Layout.fillWidth: true
              implicitHeight: remoteCardCol.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: root.bg
              border.width: 1
              border.color: root.borderCol

              ColumnLayout {
                id: remoteCardCol
                anchors.fill: parent
                anchors.margins: Style.space(12)
                spacing: Style.space(8)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(10)

                  Rectangle {
                    width: Style.space(36)
                    height: Style.space(36)
                    radius: Style.cornerRadius
                    color: root.brightCol

                    Text {
                      anchors.centerIn: parent
                      text: modelData.icon
                      font.family: Style.font.family
                      font.pixelSize: Style.font.heading
                      color: root.accentCol
                    }
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(2)

                    Text {
                      text: modelData.name + ":"
                      font.family: Style.font.family
                      font.pixelSize: Style.font.heading
                      font.weight: Font.Bold
                      color: root.fg
                    }

                    Text {
                      text: "Provider: " + modelData.provider + " (" + modelData.type + ")"
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      color: root.mutedCol
                    }
                  }

                  Rectangle {
                    visible: modelData.has_quota
                    height: Style.space(20)
                    width: pctTxt.implicitWidth + Style.space(12)
                    radius: Style.space(10)
                    color: root.accentCol

                    Text {
                      id: pctTxt
                      anchors.centerIn: parent
                      text: modelData.used_percent + "%"
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.weight: Font.Bold
                      color: Color.background
                    }
                  }
                }

                // Quota Progress bar
                Rectangle {
                  visible: modelData.has_quota
                  Layout.fillWidth: true
                  height: Style.space(8)
                  radius: Style.space(4)
                  color: root.brightCol

                  Rectangle {
                    height: parent.height
                    width: parent.width * (Math.min(100, Math.max(0, modelData.used_percent)) / 100.0)
                    radius: Style.space(4)
                    color: root.accentCol
                  }
                }

                // Stats breakdown
                RowLayout {
                  visible: modelData.has_quota
                  Layout.fillWidth: true
                  spacing: Style.space(12)

                  Text {
                    text: "Used: " + modelData.used_formatted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: root.fg
                  }

                  Text {
                    text: "Free: " + modelData.free_formatted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: root.fg
                  }

                  Text {
                    text: "Total: " + modelData.total_formatted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: root.fg
                  }

                  Text {
                    visible: Boolean(modelData.trash_formatted && modelData.trash_formatted !== "0 B")
                    text: "Trash: " + modelData.trash_formatted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: root.mutedCol
                  }
                }
              }
            }
          }
        }
      }

      // =========================================================== TAB 3: MOUNTS
      Flickable {
        anchors.fill: parent
        visible: root.currentTab === 3
        contentHeight: mountsCol.implicitHeight
        clip: true

        ColumnLayout {
          id: mountsCol
          width: parent.width
          spacing: Style.space(10)

          Text {
            visible: mounts.length === 0
            text: "No active FUSE rclone mounts detected on this system."
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: root.mutedCol
          }

          Repeater {
            model: mounts
            delegate: Rectangle {
              Layout.fillWidth: true
              implicitHeight: mountCardCol.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: root.bg
              border.width: 1
              border.color: root.borderCol

              RowLayout {
                id: mountCardCol
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(10)

                Rectangle {
                  width: Style.space(32)
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  color: root.brightCol

                  Text {
                    anchors.centerIn: parent
                    text: "󱡶"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    color: root.accentCol
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(2)

                  Text {
                    text: modelData.target
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.weight: Font.DemiBold
                    color: root.fg
                  }

                  Text {
                    text: "Source: " + modelData.source + "  ·  FUSE (rw)"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: root.mutedCol
                  }
                }

                // Open Folder Button
                Rectangle {
                  implicitHeight: Style.space(28)
                  implicitWidth: Style.space(28)
                  radius: Style.cornerRadius
                  color: openFolderMouse.containsMouse ? root.brightCol : "transparent"
                  border.width: 1
                  border.color: root.borderCol

                  Text {
                    anchors.centerIn: parent
                    text: "󰉍"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    color: root.fg
                  }

                  MouseArea {
                    id: openFolderMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runAction("open_folder", modelData.target)
                  }
                }

                // Unmount Button
                Rectangle {
                  implicitHeight: Style.space(28)
                  implicitWidth: unmountTxt.implicitWidth + Style.space(16)
                  radius: Style.cornerRadius
                  color: unmountMouse.containsMouse ? root.brightCol : "transparent"
                  border.width: 1
                  border.color: root.borderCol

                  Text {
                    id: unmountTxt
                    anchors.centerIn: parent
                    text: "Unmount"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: root.fg
                  }

                  MouseArea {
                    id: unmountMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runAction("unmount", modelData.target)
                  }
                }
              }
            }
          }
        }
      }

      // =========================================================== TAB 4: HISTORY
      Flickable {
        anchors.fill: parent
        visible: root.currentTab === 4
        contentHeight: historyCol.implicitHeight
        clip: true

        ColumnLayout {
          id: historyCol
          width: parent.width
          spacing: Style.space(8)

          Text {
            visible: history.length === 0
            text: "No recent sync runs found in systemd journal."
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: root.mutedCol
          }

          Repeater {
            model: history
            delegate: Rectangle {
              Layout.fillWidth: true
              height: Style.space(36)
              radius: Style.cornerRadius
              color: root.bg
              border.width: 1
              border.color: root.borderCol

              RowLayout {
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(8)

                Text {
                  text: modelData.status === "success" ? "✅" : "❌"
                  font.pixelSize: Style.font.caption
                }

                Text {
                  text: modelData.profile
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.weight: Font.DemiBold
                  color: root.fg
                }

                Text {
                  text: modelData.message
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: root.mutedCol
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                Text {
                  text: modelData.time
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: root.mutedCol
                }
              }
            }
          }
        }
      }
    }
  }
}
