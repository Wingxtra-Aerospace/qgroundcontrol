/****************************************************************************
 *
 * (c) 2009-2020 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

import QtQuick

import QGroundControl
import QGroundControl.Controls
import QGroundControl.ScreenTools
import QGroundControl.Vehicle
import QGroundControl.Palette

Rectangle {
    id:     root
    width:  size
    height: size
    radius: width / 2
    color:  qgcPal.window
    border.color:   qgcPal.text
    border.width:   usedByMultipleVehicleList ? 1 : 0
    opacity:        vehicle && usedByMultipleVehicleList && !vehicle.armed ? 0.5 : 1

    property real size:                         _defaultSize
    property var  vehicle:                      null
    property bool usedByMultipleVehicleList:    false

    property real _defaultSize:                 usedByMultipleVehicleList ? ScreenTools.defaultFontPixelHeight * 3 : ScreenTools.defaultFontPixelHeight * 10
    property real _sizeRatio:                   (usedByMultipleVehicleList || ScreenTools.isTinyScreen) ? (size / _defaultSize) * 0.5 : size / _defaultSize
    property int  _fontSize:                    ScreenTools.defaultFontPointSize * _sizeRatio < 8 ? 8 : ScreenTools.defaultFontPointSize * _sizeRatio
    property real _heading:                     vehicle ? vehicle.heading.rawValue : 0
    property real _headingToHome:               vehicle ? vehicle.headingToHome.rawValue : 0
    property real _groundSpeed:                 vehicle ? vehicle.groundSpeed.rawValue : 0
    property real _headingToNextWP:             vehicle ? vehicle.headingToNextWP.rawValue : 0
    property real _courseOverGround:            vehicle ? vehicle.gps.courseOverGround.rawValue : 0
    property var  _flyViewSettings:             QGroundControl.settingsManager.flyViewSettings
    property bool _showAdditionalIndicators:    _flyViewSettings.showAdditionalIndicatorsCompass.value && !usedByMultipleVehicleList
    property bool _lockNoseUpCompass:           _flyViewSettings.lockNoseUpCompass.value && !usedByMultipleVehicleList
    property var  _vehicleIconColorPalette: [
        "#F96442", // warm red-orange
        "#3CC1FE", // sky blue
        "#64DF72", // green
        "#FCC747", // amber
        "#C282FA", // violet
        "#26E0C9", // aqua
        "#FB86C3", // pink
        "#9CDF40"  // lime
    ]
    property color _headingIndicatorColor: usedByMultipleVehicleList
        ? _vehicleIconColorForId(vehicle ? vehicle.id : "active")
        : "#EE3424"
    property color _headingIndicatorSecondaryColor: Qt.darker(_headingIndicatorColor, 1.2)

    function _vehicleIconColorForId(vehicleId) {
        const key = String(vehicleId === undefined || vehicleId === null ? "active" : vehicleId)
        let hash = 0
        for (let i = 0; i < key.length; i++) {
            hash = ((hash * 31) + key.charCodeAt(i)) >>> 0
        }

        const palette = _vehicleIconColorPalette
        if (!palette || palette.length === 0) {
            return "white"
        }

        return palette[hash % palette.length]
    }

    function showCOG(){
        if (_groundSpeed < 0.5) {
            return false
        } else{
            return vehicle && _showAdditionalIndicators
        }
    }

    function showHeadingHome() {
        return vehicle && _showAdditionalIndicators && !isNaN(_headingToHome)
    }

    function showHeadingToNextWP() {
        return vehicle && _showAdditionalIndicators && !isNaN(_headingToNextWP)
    }

    function translateCenterToAngleX(radius, angle) {
        return radius * Math.sin(angle * (Math.PI / 180))
    } 

    function translateCenterToAngleY(radius, angle) {
        return -radius * Math.cos(angle * (Math.PI / 180))
    }

    QGCPalette { id: qgcPal; colorGroupEnabled: enabled }

    Item {
        id:             rotationParent
        anchors.fill:   parent

        transform: Rotation {
            origin.x:       rotationParent.width  / 2
            origin.y:       rotationParent.height / 2
            angle:         _lockNoseUpCompass ? -_heading : 0
        }

        CompassDial {
            anchors.fill:   parent
            visible:        !usedByMultipleVehicleList
        }

        CompassHeadingIndicator {
            compassSize:    size
            heading:        _heading
            simplified:     usedByMultipleVehicleList
            indicatorColor: _headingIndicatorColor
            indicatorSecondaryColor: _headingIndicatorSecondaryColor
        }

        Image {
            id:                 cogPointer
            source:             "/qmlimages/cOGPointer.svg"
            mipmap:             true
            fillMode:           Image.PreserveAspectFit
            anchors.fill:       parent
            sourceSize.height:  parent.height
            visible:            showCOG()

            transform: Rotation {
                origin.x:   cogPointer.width  / 2
                origin.y:   cogPointer.height / 2
                angle:      _courseOverGround
            }
        }

        Image {
            id:                 nextWPPointer
            source:             "/qmlimages/compassDottedLine.svg"
            mipmap:             true
            fillMode:           Image.PreserveAspectFit
            anchors.fill:       parent
            sourceSize.height:  parent.height
            visible:            showHeadingToNextWP()

            transform: Rotation {
                origin.x:   nextWPPointer.width  / 2
                origin.y:   nextWPPointer.height / 2
                angle:      _headingToNextWP
            }
        }

        // Launch location indicator
        Rectangle {
            width:              Math.max(label.contentWidth, label.contentHeight)
            height:             width
            color:              qgcPal.mapIndicator
            radius:             width / 2
            anchors.centerIn:   parent
            visible:            showHeadingHome()

            QGCLabel {
                id:                 label
                text:               qsTr("L")
                font.bold:          true
                color:              qgcPal.text
                anchors.centerIn:   parent
            }

            transform: Translate {
                property double _angle: _headingToHome

                x: translateCenterToAngleX(parent.width / 2, _angle)
                y: translateCenterToAngleY(parent.height / 2, _angle)
            }
        }
    }

    QGCLabel {
        anchors.horizontalCenter:   parent.horizontalCenter
        y:                          size * 0.74
        text:                       vehicle && !usedByMultipleVehicleList ? _heading.toFixed(0) + "°" : ""
        horizontalAlignment:        Text.AlignHCenter
    }
}
