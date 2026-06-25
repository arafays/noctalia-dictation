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

        NIcon {
          icon: "microphone"
          color: Color.mPrimary
          applyUiScale: false
          Layout.preferredWidth: Style.fontSizeL * 1.2
          Layout.preferredHeight: Style.fontSizeL * 1.2
        }

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
            pluginApi?.closePanel(pluginApi?.panelOpenScreen)
          }
        }
      }

      NText {
        text: pluginApi?.tr("panel.history") || "Recent transcriptions"
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeS
      }

      Rectangle {
        Layout.fillWidth: true
        visible: pluginApi?.mainInstance?.backendState === "recording"
        color: Color.mErrorContainer
        radius: Style.radiusM
        implicitHeight: liveSessionCol.implicitHeight + Style.marginM * 2
        height: implicitHeight

        ColumnLayout {
          id: liveSessionCol
          anchors {
            fill: parent
            margins: Style.marginM
          }
          spacing: Style.marginXS

          NText {
            text: pluginApi?.tr("panel.liveSession") || "Live session"
            color: Color.mOnErrorContainer
            font.weight: Font.Medium
          }

          NText {
            Layout.fillWidth: true
            text: {
              var mi = pluginApi?.mainInstance
              var committed = mi?.liveTranscript || ""
              var partial = mi?.partialTranscript || ""
              if (committed && partial) return committed + " " + partial
              return committed || partial || (pluginApi?.tr("panel.listening") || "Listening...")
            }
            color: Color.mOnErrorContainer
            pointSize: Style.fontSizeM
            wrapMode: Text.WordWrap
            maximumLineCount: 4
            elide: Text.ElideRight
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

                NIcon {
                  icon: "microphone"
                  color: Color.mPrimary
                  Layout.alignment: Qt.AlignTop
                  Layout.topMargin: 2
                  opacity: 0.5
                  applyUiScale: false
                }

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
                      ToastService.showNotice(pluginApi?.tr("notification.copied") || "Transcription copied to clipboard")
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

        // Empty state
        Item {
          visible: (pluginApi?.mainInstance?.history || []).length === 0
          anchors.centerIn: parent
          width: emptyColumn.implicitWidth
          height: emptyColumn.implicitHeight

          ColumnLayout {
            id: emptyColumn
            anchors.centerIn: parent
            spacing: Style.marginS

            NIcon {
              icon: "microphone-off"
              color: Color.mOnSurfaceVariant
              Layout.alignment: Qt.AlignHCenter
              Layout.preferredWidth: Style.iconSizeXL
              Layout.preferredHeight: Style.iconSizeXL
              opacity: 0.4
              applyUiScale: false
            }

            NText {
              text: pluginApi?.tr("panel.empty") || "No transcriptions yet"
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeM
              Layout.alignment: Qt.AlignHCenter
            }

            NText {
              text: pluginApi?.tr("panel.emptyHint") || "Click the mic icon in the bar to start"
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeS
              opacity: 0.6
              Layout.alignment: Qt.AlignHCenter
            }
          }
        }
      }
    }
  }
}
