/****************************************************************************
 *
 * (c) 2009-2020 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Palette
import QGroundControl.MultiVehicleManager
import QGroundControl.ScreenTools
import QGroundControl.Controllers

Rectangle {
    id:     _root
    width:  parent.width
    height: ScreenTools.toolbarHeight
    color:  qgcPal.toolbarBackground

    property var    planMasterController

    property var    _activeVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    property var    _managerVehicle:        planMasterController ? planMasterController.managerVehicle : null
    property bool   _managerVehicleOffline: _managerVehicle ? _managerVehicle.isOfflineEditingVehicle : true
    property string _uploadTargetText:      !_managerVehicle ? qsTr("No Vehicle") : (_managerVehicleOffline ? qsTr("Offline Editing Vehicle") : qsTr("Vehicle %1").arg(_managerVehicle.id))
    property string _dateTimeText:          ""

    function _updateDateTimeText() {
        _dateTimeText = Qt.formatDateTime(new Date(), "ddd, dd MMM yyyy  HH:mm:ss")
    }
    
    QGCPalette { id: qgcPal }

    /// Bottom single pixel divider
    Rectangle {
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.bottom: parent.bottom
        height:         1
        color:          "black"
        visible:        qgcPal.globalTheme === QGCPalette.Light
    }

    RowLayout {
        id:                     viewButtonRow
        anchors.bottomMargin:   1
        anchors.top:            parent.top
        anchors.bottom:         parent.bottom
        spacing:                ScreenTools.defaultFontPixelWidth / 2

        QGCLabel {
            font.pointSize: ScreenTools.largeFontPointSize
            text:           "<"
        }

        QGCLabel {
            text:           qsTr("Exit Plan")
            font.pointSize: ScreenTools.largeFontPointSize
        }
    }

    QGCMouseArea {
        anchors.fill:   viewButtonRow
        onClicked:      mainWindow.showFlyView()
    }

    QGCFlickable {
        id:                     toolsFlickable
        //anchors.leftMargin:     ScreenTools.defaultFontPixelWidth * ScreenTools.largeFontPointRatio * 1.5
        anchors.left:           viewButtonRow.right
        anchors.bottomMargin:   1
        anchors.top:            parent.top
        anchors.bottom:         parent.bottom
        anchors.right:          uploadTargetContainer.left
        anchors.rightMargin:    ScreenTools.defaultFontPixelWidth * 0.5
        contentWidth:           toolIndicators.width
        flickableDirection:     Flickable.HorizontalFlick

        PlanToolBarIndicators {
            id:                     toolIndicators
            anchors.top:            parent.top
            anchors.bottom:         parent.bottom
            planMasterController:   _root.planMasterController
        }
    }

    Rectangle {
        id:                     uploadTargetContainer
        anchors.right:          dateTimeContainer.left
        anchors.top:            parent.top
        anchors.bottom:         parent.bottom
        anchors.margins:        ScreenTools.defaultFontPixelHeight * 0.42
        anchors.rightMargin:    ScreenTools.defaultFontPixelWidth * 0.5
        radius:                 ScreenTools.defaultFontPixelHeight * 0.2
        color:                  Qt.rgba(0, 0, 0, 0.2)
        border.width:           qgcPal.globalTheme === QGCPalette.Light ? 1 : 0
        border.color:           Qt.rgba(1, 1, 1, 0.2)
        width:                  Math.max(uploadTargetTitleLabel.implicitWidth, uploadTargetValueLabel.implicitWidth) + (ScreenTools.defaultFontPixelWidth * 1.8)

        Column {
            anchors.centerIn:   parent
            spacing:            0

            QGCLabel {
                id:                 uploadTargetTitleLabel
                text:               qsTr("Upload Target")
                font.pointSize:     ScreenTools.smallFontPointSize * 1.2
                opacity:            0.75
                horizontalAlignment: Text.AlignHCenter
                width:              implicitWidth
            }

            QGCLabel {
                id:                 uploadTargetValueLabel
                text:               _uploadTargetText
                font.pointSize:     ScreenTools.defaultFontPointSize * 1.2
                font.weight:        Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                width:              implicitWidth
            }
        }
    }

    Rectangle {
        id:                     dateTimeContainer
        anchors.right:          parent.right
        anchors.top:            parent.top
        anchors.bottom:         parent.bottom
        anchors.margins:        ScreenTools.defaultFontPixelHeight * 0.42
        radius:                 ScreenTools.defaultFontPixelHeight * 0.2
        color:                  Qt.rgba(0, 0, 0, 0.25)
        border.width:           qgcPal.globalTheme === QGCPalette.Light ? 1 : 0
        border.color:           Qt.rgba(1, 1, 1, 0.2)
        width:                  dateTimeLabel.implicitWidth + (ScreenTools.defaultFontPixelWidth * 1.8)
        visible:                _dateTimeText.length > 0

        QGCLabel {
            id:                 dateTimeLabel
            anchors.centerIn:   parent
            text:               _dateTimeText
            font.pointSize:     ScreenTools.defaultFontPointSize
            font.family:        ScreenTools.normalFontFamily
            color:              qgcPal.buttonText
            verticalAlignment:  Text.AlignVCenter
        }
    }

    Timer {
        id:             dateTimeTimer
        interval:       1000
        running:        true
        repeat:         true
        onTriggered:    _updateDateTimeText()
    }

    Component.onCompleted: _updateDateTimeText()
}
