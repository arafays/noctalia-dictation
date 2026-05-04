import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
  id: root

  property var pluginApi: null

  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true

  property real contentPreferredWidth: 600 * Style.uiScaleRatio
  property real contentPreferredHeight: 500 * Style.uiScaleRatio

  anchors.fill: parent

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      anchors {
        fill: parent
        margins: Style.marginL
      }
      spacing: Style.marginM

      RowLayout {
        Layout.fillWidth: true

        NText {
          text: pluginApi?.tr("panel.title") || "Dictation"
          pointSize: Style.fontSizeL
          font.weight: Font.Bold
          color: Color.mOnSurface
          Layout.fillWidth: true
        }

        NIconButton {
          icon: "trash"
          tooltipText: pluginApi?.tr("panel.clear") || "Clear history"
          Layout.topMargin: Style.marginS
          Layout.bottomMargin: Style.marginS
          onClicked: {
            if (pluginApi?.mainInstance) {
              pluginApi.mainInstance.clearHistory()
            }
          }
        }

        NIconButton {
          icon: "x"
          Layout.topMargin: Style.marginS
          Layout.bottomMargin: Style.marginS
          onClicked: {
            pluginApi.closePanel(pluginApi.panelOpenScreen)
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurfaceVariant
        radius: Style.radiusL
        border.width: 0

        NScrollView {
          anchors.fill: parent

          ListView {
            id: historyList
            anchors.fill: parent
            anchors.margins: Style.marginM

            model: pluginApi?.mainInstance?.history || []
            spacing: Style.marginS

            delegate: Rectangle {
              id: historyDelegate
              width: historyList.width - Style.marginM * 2
              height: contentCol.implicitHeight + Style.marginM * 2
              x: Style.marginM
              color: delegateMouseArea.containsMouse ? Color.mSurfaceContainerHighest : Color.mSurface
              radius: Style.radiusM

              Behavior on color {
                ColorAnimation { duration: 100 }
              }

              MouseArea {
                id: delegateMouseArea
                anchors.fill: parent
                hoverEnabled: true
              }

              RowLayout {
                anchors {
                  fill: parent
                  margins: Style.marginM
                }
                spacing: Style.marginS

                ColumnLayout {
                  id: contentCol
                  Layout.fillWidth: true
                  spacing: 2

                  NText {
                    id: textItem
                    text: (typeof modelData === "object" ? modelData.text : modelData) || ""
                    color: Color.mOnSurface
                    pointSize: Style.fontSizeM
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                  }

                  NText {
                    visible: typeof modelData === "object" && modelData.timestamp
                    text: {
                      if (typeof modelData === "object" && modelData.timestamp) {
                        return Qt.formatDateTime(new Date(modelData.timestamp), "hh:mm")
                      }
                      return ""
                    }
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeXS
                  }
                }

                RowLayout {
                  spacing: Style.marginXS
                  visible: delegateMouseArea.containsMouse
                  Layout.alignment: Qt.AlignTop

                  NIconButton {
                    icon: "copy"
                    baseSize: Style.iconSizeS
                    tooltipText: pluginApi?.tr("panel.copy") || "Copy to clipboard"
                    onClicked: {
                      var txt = (typeof modelData === "object" ? modelData.text : modelData) || ""
                      Quickshell.execDetached(["wl-copy", txt])
                      ToastService.showNotice("Copied to clipboard")
                    }
                  }

                  NIconButton {
                    icon: "keyboard"
                    baseSize: Style.iconSizeS
                    tooltipText: pluginApi?.tr("panel.retype") || "Type again"
                    property string pendingText: ""
                    Timer {
                      id: pasteDelayTimer
                      interval: 150
                      onTriggered: Quickshell.execDetached(["wtype", "-M", "ctrl", "v", "-m", "ctrl"])
                    }
                    onClicked: {
                      var txt = (typeof modelData === "object" ? modelData.text : modelData) || ""
                      Quickshell.execDetached(["wl-copy", txt])
                      pasteDelayTimer.restart()
                    }
                  }
                }
              }
            }
          }
        }

        NText {
          visible: (pluginApi?.mainInstance?.history || []).length === 0
          anchors.centerIn: parent
          z: 1
          text: pluginApi?.tr("panel.empty") || "No transcriptions yet"
          color: Color.mOnSurfaceVariant
          pointSize: Style.fontSizeM
        }
      }

      NText {
        text: pluginApi?.tr("panel.history") || "Recent transcriptions"
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeS
        Layout.topMargin: Style.marginS
      }
    }
  }
}
