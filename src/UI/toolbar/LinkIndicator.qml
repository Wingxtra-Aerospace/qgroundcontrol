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

import QGroundControl
import QGroundControl.Controls
import QGroundControl.MultiVehicleManager
import QGroundControl.ScreenTools
import QGroundControl.Palette
import QGroundControl.Vehicle

Item {
    anchors.top:    parent.top
    anchors.bottom: parent.bottom
    width:          showIndicator ? linkBadge.implicitWidth : 0

    property bool   showIndicator:       !!_activeVehicle
    property var    _activeVehicle:      QGroundControl.multiVehicleManager.activeVehicle
    property var    _rgLinkNames:        _activeVehicle ? _activeVehicle.vehicleLinkManager.linkNames : [ ]
    property var    _rgLinkStatus:       _activeVehicle ? _activeVehicle.vehicleLinkManager.linkStatuses : [ ]
    property string _primaryLinkName:    _activeVehicle ? _activeVehicle.vehicleLinkManager.primaryLinkName : ""
    property bool   _communicationLost:  _activeVehicle ? _activeVehicle.vehicleLinkManager.communicationLost : false
    property var    _linkEntries:        [ ]

    QGCPalette { id: qgcPal }

    function _parsePacketLoss(statusText) {
        if (!statusText) {
            return 0
        }
        const match = statusText.toString().match(/([0-9]+)\s*%/i)
        if (match && match.length > 1) {
            return parseInt(match[1])
        }
        return 0
    }

    function _maxPacketLoss() {
        let maxLoss = 0
        for (let i = 0; i < _rgLinkStatus.length; i++) {
            maxLoss = Math.max(maxLoss, _parsePacketLoss(_rgLinkStatus[i]))
        }
        return maxLoss
    }

    function _qualityLevel() {
        if (_communicationLost) {
            return qsTr("Critical")
        }
        const maxLoss = _maxPacketLoss()
        if (maxLoss >= 30) {
            return qsTr("Poor")
        } else if (maxLoss >= 10) {
            return qsTr("Fair")
        }
        return qsTr("Good")
    }

    function _qualityColor() {
        if (_communicationLost) {
            return qgcPal.colorRed
        }
        const maxLoss = _maxPacketLoss()
        if (maxLoss >= 30) {
            return qgcPal.colorOrange
        } else if (maxLoss >= 10) {
            return qgcPal.colorYellow
        }
        return qgcPal.colorGreen
    }

    function _refreshLinkEntries() {
        const entries = [ ]
        for (let i = 0; i < _rgLinkNames.length; i++) {
            entries.push({
                name: _rgLinkNames[i],
                status: _rgLinkStatus[i],
                isPrimary: _primaryLinkName === _rgLinkNames[i]
            })
        }
        _linkEntries = entries
    }

    function _openLinkDetails() {
        if (!_activeVehicle) {
            return
        }
        _refreshLinkEntries()
        mainWindow.showIndicatorDrawer(linkIndicatorPage, linkBadge)
    }

    Component.onCompleted: _refreshLinkEntries()
    on_RgLinkNamesChanged: _refreshLinkEntries()
    on_RgLinkStatusChanged: _refreshLinkEntries()
    on_PrimaryLinkNameChanged: _refreshLinkEntries()

    Rectangle {
        id:                     linkBadge
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth:          badgeContent.implicitWidth + (ScreenTools.defaultFontPixelWidth * 1.3)
        implicitHeight:         parent.height * 0.72
        radius:                 ScreenTools.buttonBorderRadius
        color:                  qgcPal.button
        border.width:           1
        border.color:           qgcPal.groupBorder
        visible:                showIndicator

        RowLayout {
            id:                     badgeContent
            anchors.fill:           parent
            anchors.leftMargin:     ScreenTools.defaultFontPixelWidth * 0.6
            anchors.rightMargin:    ScreenTools.defaultFontPixelWidth * 0.6
            spacing:                ScreenTools.defaultFontPixelWidth * 0.45

            Rectangle {
                width:      ScreenTools.defaultFontPixelHeight * 0.52
                height:     width
                radius:     width / 2
                color:      _qualityColor()
            }

            QGCLabel {
                text:               qsTr("Link %1").arg(_qualityLevel())
                font.pointSize:     ScreenTools.defaultFontPointSize
                font.weight:        Font.Medium
            }

            QGCLabel {
                visible:            _primaryLinkName.length > 0
                text:               _primaryLinkName
                font.pointSize:     ScreenTools.smallFontPointSize
                opacity:            0.72
            }
        }

        MouseArea {
            anchors.fill:   parent
            onClicked:      _openLinkDetails()
        }
    }

    Component {
        id: linkIndicatorPage

        ToolIndicatorPage {
            contentComponent: Component {
                ColumnLayout {
                    spacing:    ScreenTools.defaultDialogControlSpacing

                    QGCLabel {
                        text:           qsTr("Connection Quality")
                        font.pointSize: ScreenTools.mediumFontPointSize
                        font.weight:    Font.DemiBold
                    }

                    RowLayout {
                        spacing: ScreenTools.defaultFontPixelWidth * 0.5

                        Rectangle {
                            width:      ScreenTools.defaultFontPixelHeight * 0.65
                            height:     width
                            radius:     width / 2
                            color:      _qualityColor()
                        }

                        QGCLabel {
                            text: qsTr("%1 (%2 links)").arg(_qualityLevel()).arg(Math.max(1, _rgLinkNames.length))
                        }
                    }

                    Repeater {
                        model: _linkEntries

                        delegate: Rectangle {
                            Layout.fillWidth:   true
                            implicitHeight:     linkRow.implicitHeight + (ScreenTools.defaultFontPixelHeight * 0.52)
                            radius:             ScreenTools.buttonBorderRadius
                            color:              qgcPal.button
                            border.width:       1
                            border.color:       modelData.isPrimary ? qgcPal.brandingBlue : qgcPal.groupBorder

                            RowLayout {
                                id:                     linkRow
                                anchors.fill:           parent
                                anchors.margins:        ScreenTools.defaultFontPixelHeight * 0.3
                                spacing:                ScreenTools.defaultFontPixelWidth * 0.6

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    QGCLabel {
                                        text:           modelData.name
                                        font.weight:    modelData.isPrimary ? Font.DemiBold : Font.Normal
                                    }

                                    QGCLabel {
                                        visible:        modelData.status && modelData.status.length > 0
                                        text:           modelData.status
                                        font.pointSize: ScreenTools.smallFontPointSize
                                        opacity:        0.75
                                    }
                                }

                                QGCButton {
                                    text:               modelData.isPrimary ? qsTr("Primary") : qsTr("Set Primary")
                                    enabled:            !modelData.isPrimary
                                    onClicked: {
                                        _activeVehicle.vehicleLinkManager.primaryLinkName = modelData.name
                                        _refreshLinkEntries()
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        spacing: ScreenTools.defaultFontPixelWidth * 0.5

                        QGCButton {
                            text:       qsTr("Comm Links")
                            onClicked: {
                                mainWindow.showSettingsTool("Comm Links")
                                mainWindow.closeIndicatorDrawer()
                            }
                        }

                        QGCButton {
                            text:       qsTr("Disconnect")
                            enabled:    _activeVehicle
                            onClicked: {
                                _activeVehicle.closeVehicle()
                                mainWindow.closeIndicatorDrawer()
                            }
                        }
                    }
                }
            }
        }
    }
}
