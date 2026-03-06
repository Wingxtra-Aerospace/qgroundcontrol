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

import QGroundControl
import QGroundControl.Controls
import QGroundControl.ScreenTools
import QGroundControl.SettingsManager

/// Map scale control
Item {
    id:     scale
    width:  buttonsOnLeft || !_zoomButtonsVisible ? rightEnd.x + rightEnd.width : zoomDownButton.x + zoomDownButton.width
    height: rightEnd.y + rightEnd.height

    property var    mapControl                      ///< Map control for which this scale control is being used
    property bool   terrainButtonVisible:   false
    property alias  terrainButtonChecked:   terrainButton.checked
    property bool   zoomButtonsVisible:     true
    property bool   buttonsOnLeft:          true    ///< Buttons to left/right of scale bar

    signal terrainButtonClicked

    property var    _scaleLengthsMeters:    [5, 10, 25, 50, 100, 150, 250, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000, 500000, 1000000, 2000000]
    property var    _scaleLengthsFeet:      [10, 25, 50, 100, 250, 500, 1000, 2000, 3000, 4000, 5280, 5280*2, 5280*5, 5280*10, 5280*25, 5280*50, 5280*100, 5280*250, 5280*500, 5280*1000]
    property bool   _zoomButtonsVisible:    zoomButtonsVisible && !ScreenTools.isMobile
    property bool   _mapSupportsScaleDistance: mapControl && typeof mapControl.toCoordinate === "function"
    property bool   _mapSupportsAsyncScaleDistance: mapControl && typeof mapControl.getScaleLineMeters === "function"
    property var    _color:                 mapControl && mapControl.isSatelliteMap === true ? "white" : "black"

    function _changeZoom(zoomStep) {
        if (!mapControl) {
            return
        }

        const step = Number(zoomStep)
        if (!isFinite(step) || step === 0) {
            return
        }

        if (typeof mapControl.stepZoom === "function") {
            mapControl.stepZoom(step)
        } else if (mapControl.zoomLevel !== undefined) {
            const zoom = Number(mapControl.zoomLevel)
            if (!isFinite(zoom)) {
                return
            }
            mapControl.zoomLevel = zoom + step
        }

        scaleTimer.restart()
    }

    function formatDistanceMeters(meters) {
        var dist = Math.round(meters)
        if (dist > 1000 ){
            if (dist > 100000){
                dist = Math.round(dist / 1000)
            } else {
                dist = Math.round(dist / 100)
                dist = dist / 10
            }
            dist = dist + qsTr(" km")
        } else {
            dist = dist + qsTr(" m")
        }
        return dist
    }

    function formatDistanceFeet(feet) {
        var dist = Math.round(feet)
        if (dist >= 5280) {
            dist = Math.round(dist / 5280)
            dist = dist
            if (dist == 1) {
                dist += qsTr(" mile")
            } else {
                dist += qsTr(" miles")
            }
        } else {
            dist = dist + qsTr(" ft")
        }
        return dist
    }

    function calculateMetersRatio(scaleLineMeters, scaleLinePixelLength) {
        var scaleLineRatio = 0

        if (scaleLineMeters === 0) {
            // not visible
        } else {
            for (var i = 0; i < _scaleLengthsMeters.length - 1; i++) {
                if (scaleLineMeters < (_scaleLengthsMeters[i] + _scaleLengthsMeters[i+1]) / 2 ) {
                    scaleLineRatio = _scaleLengthsMeters[i] / scaleLineMeters
                    scaleLineMeters = _scaleLengthsMeters[i]
                    break;
                }
            }
            if (scaleLineRatio === 0) {
                scaleLineRatio = scaleLineMeters / _scaleLengthsMeters[i]
                scaleLineMeters = _scaleLengthsMeters[i]
            }
        }

        var text = formatDistanceMeters(scaleLineMeters)
        centerLine.width = (scaleLinePixelLength * scaleLineRatio) - (2 * leftEnd.width)
        scaleText.text = text
    }

    function calculateFeetRatio(scaleLineMeters, scaleLinePixelLength) {
        var scaleLineRatio = 0
        var scaleLineFeet = scaleLineMeters * 3.2808399

        if (scaleLineFeet === 0) {
            // not visible
        } else {
            for (var i = 0; i < _scaleLengthsFeet.length - 1; i++) {
                if (scaleLineFeet < (_scaleLengthsFeet[i] + _scaleLengthsFeet[i+1]) / 2 ) {
                    scaleLineRatio = _scaleLengthsFeet[i] / scaleLineFeet
                    scaleLineFeet = _scaleLengthsFeet[i]
                    break;
                }
            }
            if (scaleLineRatio === 0) {
                scaleLineRatio = scaleLineFeet / _scaleLengthsFeet[i]
                scaleLineFeet = _scaleLengthsFeet[i]
            }
        }

        var text = formatDistanceFeet(scaleLineFeet)
        centerLine.width = (scaleLinePixelLength * scaleLineRatio) - (2 * leftEnd.width)
        scaleText.text = text
    }

    function calculateScale() {
        if (!mapControl) {
            return
        }

        var scaleLinePixelLength = 100

        if (_mapSupportsAsyncScaleDistance) {
            mapControl.getScaleLineMeters(scaleLinePixelLength, scale.y, function(scaleLineMeters) {
                const meters = Math.round(Number(scaleLineMeters))
                if (!isFinite(meters) || meters <= 0) {
                    return
                }

                if (QGroundControl.settingsManager.unitsSettings.horizontalDistanceUnits.value === UnitsSettings.HorizontalDistanceUnitsFeet) {
                    calculateFeetRatio(meters, scaleLinePixelLength)
                } else {
                    calculateMetersRatio(meters, scaleLinePixelLength)
                }
            })
            return
        }

        if (!_mapSupportsScaleDistance) {
            return
        }

        var leftCoord  = mapControl.toCoordinate(Qt.point(0, scale.y), false /* clipToViewPort */)
        var rightCoord = mapControl.toCoordinate(Qt.point(scaleLinePixelLength, scale.y), false /* clipToViewPort */)
        var scaleLineMeters = Math.round(leftCoord.distanceTo(rightCoord))
        if (QGroundControl.settingsManager.unitsSettings.horizontalDistanceUnits.value === UnitsSettings.HorizontalDistanceUnitsFeet) {
            calculateFeetRatio(scaleLineMeters, scaleLinePixelLength)
        } else {
            calculateMetersRatio(scaleLineMeters, scaleLinePixelLength)
        }
    }

    Connections {
        ignoreUnknownSignals: true
        target:             mapControl
        function onWidthChanged() {     scaleTimer.restart() }
        function onHeightChanged() {    scaleTimer.restart() }
        function onZoomLevelChanged() { scaleTimer.restart() }
    }

    onMapControlChanged:   scaleTimer.restart()
    onVisibleChanged: {
        if (visible) {
            scaleTimer.restart()
        }
    }

    Timer {
        id:                 scaleTimer
        interval:           100
        running:            false
        repeat:             false
        onTriggered:        calculateScale()
    }

    Timer {
        id:                 liveScaleTimer
        interval:           220
        running:            scale.visible && _mapSupportsAsyncScaleDistance
        repeat:             true
        onTriggered:        calculateScale()
    }

    QGCMapLabel {
        id:                 scaleText
        map:                mapControl
        font.bold:          true
        anchors.left:       parent.left
        anchors.right:      rightEnd.right
        horizontalAlignment:Text.AlignRight
        text:               "0 m"
    }

    Rectangle {
        id:                 leftEnd
        anchors.top:        scaleText.bottom
        anchors.leftMargin: buttonsOnLeft && (_zoomButtonsVisible || terrainButtonVisible) ? ScreenTools.defaultFontPixelWidth / 2 : 0
        anchors.left:       buttonsOnLeft ?
                                (_zoomButtonsVisible ? zoomDownButton.right : (terrainButtonVisible ? terrainButton.right : parent.left)) :
                                parent.left
        width:              2
        height:             ScreenTools.defaultFontPixelHeight
        color:              _color
    }

    Rectangle {
        id:                 centerLine
        anchors.bottomMargin:   2
        anchors.bottom:     leftEnd.bottom
        anchors.left:       leftEnd.right
        height:             2
        color:              _color
    }

    Rectangle {
        id:                 rightEnd
        anchors.top:        leftEnd.top
        anchors.left:       centerLine.right
        width:              2
        height:             ScreenTools.defaultFontPixelHeight
        color:              _color
    }

    QGCButton {
        id:                 terrainButton
        anchors.top:        scaleText.top
        anchors.bottom:     rightEnd.bottom
        anchors.leftMargin: buttonsOnLeft ? 0 : ScreenTools.defaultFontPixelWidth / 2
        anchors.left:       buttonsOnLeft ? parent.left : rightEnd.right
        leftPadding:        topPadding
        iconSource:         "/res/terrain.svg"
        width:              height
        opacity:            0.75
        visible:            terrainButtonVisible
        onClicked:          terrainButtonClicked()
    }

    QGCButton {
        id:                 zoomUpButton
        anchors.top:        scaleText.top
        anchors.bottom:     rightEnd.bottom
        anchors.leftMargin: terrainButton.visible ? ScreenTools.defaultFontPixelWidth / 2 : 0
        anchors.left:       terrainButton.visible ? terrainButton.right : terrainButton.left
        text:               qsTr("+")
        width:              height
        opacity:            0.75
        visible:            _zoomButtonsVisible
        onClicked:          _changeZoom(0.5)
    }

    QGCButton {
        id:                 zoomDownButton
        anchors.top:        scaleText.top
        anchors.bottom:     rightEnd.bottom
        anchors.leftMargin: ScreenTools.defaultFontPixelWidth / 2
        anchors.left:       zoomUpButton.right
        text:               qsTr("-")
        width:              height
        opacity:            0.75
        visible:            _zoomButtonsVisible
        onClicked:          _changeZoom(-0.5)
    }

    Component.onCompleted: {
        if (scale.visible) {
            calculateScale();
        }
    }
}
