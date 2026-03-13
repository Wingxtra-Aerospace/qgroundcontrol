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

    function _linkQualityColor(statusText) {
        if (!statusText || statusText.length === 0) {
            return qgcPal.brandingBlue
        }
        const packetLoss = _parsePacketLoss(statusText)
        if (packetLoss >= 30) {
            return qgcPal.colorRed
        } else if (packetLoss >= 10) {
            return qgcPal.colorOrange
        }
        return qgcPal.colorGreen
    }

    function _linkRoleText(isPrimary) {
        return isPrimary ? qsTr("Primary") : qsTr("Secondary")
    }

    function _linkRoleAccent(isPrimary) {
        return isPrimary ? qgcPal.colorGreen : qgcPal.brandingBlue
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
        entries.sort(function (left, right) {
            if (left.isPrimary === right.isPrimary) {
                return left.name.localeCompare(right.name)
            }
            return left.isPrimary ? -1 : 1
        })
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
                    id:         linkPanel
                    spacing:    ScreenTools.defaultDialogControlSpacing * 0.9
                    width:      Math.max(
                                    ScreenTools.defaultFontPixelWidth * 36,
                                    Math.min(ScreenTools.defaultFontPixelWidth * 58, mainWindow.width * 0.42)
                                )
                    implicitWidth: width

                    QGCLabel {
                        text:           qsTr("Connection Quality")
                        font.pointSize: ScreenTools.mediumFontPointSize
                        font.weight:    Font.DemiBold
                    }

                    Rectangle {
                        Layout.fillWidth:   true
                        Layout.preferredWidth: linkPanel.width
                        radius:             ScreenTools.defaultFontPixelWidth * 0.55
                        color:              qgcPal.button
                        border.width:       1
                        border.color:       qgcPal.groupBorder
                        implicitHeight:     statusSummaryLayout.implicitHeight + (ScreenTools.defaultFontPixelHeight * 0.55)

                        RowLayout {
                            id:                     statusSummaryLayout
                            anchors.fill:           parent
                            anchors.leftMargin:     ScreenTools.defaultFontPixelWidth * 0.7
                            anchors.rightMargin:    ScreenTools.defaultFontPixelWidth * 0.7
                            anchors.topMargin:      ScreenTools.defaultFontPixelHeight * 0.2
                            anchors.bottomMargin:   ScreenTools.defaultFontPixelHeight * 0.2
                            spacing:                ScreenTools.defaultFontPixelWidth * 0.6

                            Rectangle {
                                width:      ScreenTools.defaultFontPixelHeight * 0.65
                                height:     width
                                radius:     width / 2
                                color:      _qualityColor()
                            }

                            QGCLabel {
                                Layout.fillWidth:   true
                                text:               qsTr("%1 (%2 links)").arg(_qualityLevel()).arg(Math.max(1, _rgLinkNames.length))
                                font.weight:        Font.Medium
                            }

                            Rectangle {
                                radius:         ScreenTools.defaultFontPixelHeight * 0.22
                                color:          Qt.rgba(_qualityColor().r, _qualityColor().g, _qualityColor().b, 0.16)
                                border.width:   1
                                border.color:   _qualityColor()
                                implicitHeight: qualityChipText.implicitHeight + (ScreenTools.defaultFontPixelHeight * 0.25)
                                implicitWidth:  qualityChipText.implicitWidth + (ScreenTools.defaultFontPixelWidth * 0.95)

                                QGCLabel {
                                    id:                 qualityChipText
                                    anchors.centerIn:   parent
                                    text:               _qualityLevel().toUpperCase()
                                    font.pointSize:     ScreenTools.smallFontPointSize * 0.92
                                    font.weight:        Font.DemiBold
                                    color:              _qualityColor()
                                }
                            }
                        }
                    }

                    QGCLabel {
                        Layout.fillWidth:   true
                        text:               qsTr("Primary link is highlighted. Use \"Switch\" on a secondary link to make it active.")
                        wrapMode:           Text.WordWrap
                        font.pointSize:     ScreenTools.smallFontPointSize
                        opacity:            0.78
                    }

                    Rectangle {
                        Layout.fillWidth:   true
                        Layout.preferredHeight: 1
                        color:              qgcPal.groupBorder
                        opacity:            0.8
                    }

                    Repeater {
                        model: _linkEntries

                        delegate: Rectangle {
                            readonly property color _linkColor: _linkQualityColor(modelData.status)
                            readonly property color _roleAccent: _linkRoleAccent(modelData.isPrimary)
                            Layout.fillWidth:       true
                            Layout.preferredWidth:  linkPanel.width
                            implicitHeight:         linkCardLayout.implicitHeight + (ScreenTools.defaultFontPixelHeight * 0.62)
                            radius:                 ScreenTools.buttonBorderRadius
                            color:                  modelData.isPrimary
                                                    ? Qt.rgba(_roleAccent.r, _roleAccent.g, _roleAccent.b, 0.16)
                                                    : qgcPal.button
                            border.width:           modelData.isPrimary ? 2 : 1
                            border.color:           modelData.isPrimary ? _roleAccent : qgcPal.groupBorder

                            Rectangle {
                                anchors.left:            parent.left
                                anchors.leftMargin:      ScreenTools.defaultFontPixelWidth * 0.32
                                anchors.top:             parent.top
                                anchors.bottom:          parent.bottom
                                anchors.topMargin:       ScreenTools.defaultFontPixelHeight * 0.3
                                anchors.bottomMargin:    ScreenTools.defaultFontPixelHeight * 0.3
                                width:                   ScreenTools.defaultFontPixelWidth * 0.36
                                radius:                  width / 2
                                color:                   _roleAccent
                                opacity:                 0.95
                            }

                            ColumnLayout {
                                id:                     linkCardLayout
                                anchors.fill:           parent
                                anchors.leftMargin:     ScreenTools.defaultFontPixelWidth * 1.15
                                anchors.rightMargin:    ScreenTools.defaultFontPixelWidth * 0.72
                                anchors.topMargin:      ScreenTools.defaultFontPixelHeight * 0.28
                                anchors.bottomMargin:   ScreenTools.defaultFontPixelHeight * 0.28
                                spacing:                ScreenTools.defaultFontPixelHeight * 0.18

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: ScreenTools.defaultFontPixelWidth * 0.55

                                    QGCLabel {
                                        Layout.fillWidth:   true
                                        text:               modelData.name
                                        font.weight:        Font.DemiBold
                                        elide:              Text.ElideRight
                                    }

                                    Rectangle {
                                        radius:         ScreenTools.defaultFontPixelHeight * 0.2
                                        color:          modelData.isPrimary
                                                        ? Qt.rgba(_roleAccent.r, _roleAccent.g, _roleAccent.b, 0.22)
                                                        : Qt.rgba(_roleAccent.r, _roleAccent.g, _roleAccent.b, 0.14)
                                        border.width:   1
                                        border.color:   _roleAccent
                                        implicitHeight: roleChipText.implicitHeight + (ScreenTools.defaultFontPixelHeight * 0.22)
                                        implicitWidth:  roleChipText.implicitWidth + (ScreenTools.defaultFontPixelWidth * 0.8)

                                        QGCLabel {
                                            id:                 roleChipText
                                            anchors.centerIn:   parent
                                            text:               _linkRoleText(modelData.isPrimary).toUpperCase()
                                            font.pointSize:     ScreenTools.smallFontPointSize * 0.85
                                            font.weight:        Font.DemiBold
                                            color:              _roleAccent
                                        }
                                    }
                                }

                                QGCLabel {
                                    Layout.fillWidth:   true
                                    text:               (modelData.status && modelData.status.length > 0)
                                                        ? modelData.status
                                                        : qsTr("Status unavailable")
                                    font.pointSize:     ScreenTools.smallFontPointSize
                                    color:              _linkColor
                                    wrapMode:           Text.WordWrap
                                    maximumLineCount:   2
                                    elide:              Text.ElideRight
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: ScreenTools.defaultFontPixelWidth * 0.5

                                    QGCButton {
                                        text:               modelData.isPrimary ? qsTr("Active") : qsTr("Switch")
                                        enabled:            !modelData.isPrimary
                                        onClicked: {
                                            _activeVehicle.vehicleLinkManager.primaryLinkName = modelData.name
                                            _refreshLinkEntries()
                                        }
                                    }

                                    QGCLabel {
                                        Layout.fillWidth:   true
                                        visible:            modelData.isPrimary
                                        text:               qsTr("This link currently carries priority traffic.")
                                        font.pointSize:     ScreenTools.smallFontPointSize
                                        opacity:            0.72
                                        wrapMode:           Text.WordWrap
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth:   true
                        spacing:            ScreenTools.defaultFontPixelWidth * 0.5

                        QGCButton {
                            Layout.fillWidth:   true
                            text:       qsTr("Comm Links")
                            onClicked: {
                                mainWindow.showSettingsTool("Comm Links")
                                mainWindow.closeIndicatorDrawer()
                            }
                        }

                        QGCButton {
                            Layout.fillWidth:   true
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
