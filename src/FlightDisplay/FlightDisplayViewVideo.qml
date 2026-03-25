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
import QGroundControl.FlightDisplay
import QGroundControl.FlightMap
import QGroundControl.ScreenTools
import QGroundControl.Controls
import QGroundControl.Palette
import QGroundControl.Vehicle
import QGroundControl.Controllers

Item {
    id:     root
    clip:   true

    property bool useSmallFont: true

    property double _ar:                QGroundControl.videoManager.gstreamerEnabled
                                            ? QGroundControl.videoManager.videoSize.width / QGroundControl.videoManager.videoSize.height
                                            : QGroundControl.videoManager.aspectRatio
    property bool   _showGrid:          QGroundControl.settingsManager.videoSettings.gridLines.rawValue
    property var    _dynamicCameras:    globals.activeVehicle ? globals.activeVehicle.cameraManager : null
    property bool   _connected:         globals.activeVehicle ? !globals.activeVehicle.communicationLost : false
    property int    _curCameraIndex:    _dynamicCameras ? _dynamicCameras.currentCamera : 0
    property bool   _isCamera:          _dynamicCameras ? _dynamicCameras.cameras.count > 0 : false
    property var    _camera:            _isCamera ? _dynamicCameras.cameras.get(_curCameraIndex) : null
    property bool   _hasZoom:           _camera && _camera.hasZoom
    property int    _fitMode:           QGroundControl.settingsManager.videoSettings.videoFit.rawValue

    property bool   _isMode_FIT_WIDTH:  _fitMode === 0
    property bool   _isMode_FIT_HEIGHT: _fitMode === 1
    property bool   _isMode_FILL:       _fitMode === 2
    property bool   _isMode_NO_CROP:    _fitMode === 3

    function getWidth() {
        return videoBackground.getWidth()
    }
    function getHeight() {
        return videoBackground.getHeight()
    }

    property double _thermalHeightFactor: 0.85 //-- TODO

    Rectangle {
        id:             noVideo
        anchors.fill:   parent
        visible:        !(QGroundControl.videoManager.decoding)
        color:          "#05070A"

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0D141D" }
            GradientStop { position: 0.45; color: "#070B10" }
            GradientStop { position: 1.0; color: "#020305" }
        }

        Rectangle {
            anchors.fill:       parent
            color:              "transparent"
            border.color:       "#1A2430"
            border.width:       1
            opacity:            0.45
        }

        Rectangle {
            width:              Math.min(parent.width * 0.44, ScreenTools.defaultFontPixelWidth * 34)
            height:             Math.min(parent.height * 0.24, ScreenTools.defaultFontPixelHeight * 8)
            anchors.centerIn:   parent
            radius:             ScreenTools.defaultFontPixelWidth
            color:              "#121A24"
            opacity:            0.9
            border.color:       "#2A3645"
            border.width:       1
        }

        Rectangle {
            width:              ScreenTools.defaultFontPixelWidth * 5
            height:             ScreenTools.defaultFontPixelWidth * 5
            radius:             width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter:   parent.verticalCenter
            anchors.verticalCenterOffset: -ScreenTools.defaultFontPixelHeight * 1.4
            color:              "#0E2632"
            border.color:       "#3C8DFF"
            border.width:       1
            opacity:            0.95

            Rectangle {
                width:          parent.width * 0.46
                height:         parent.height * 0.30
                radius:         ScreenTools.defaultFontPixelWidth * 0.3
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -ScreenTools.defaultFontPixelWidth * 0.1
                color:          "transparent"
                border.color:   "#D7E8FF"
                border.width:   1
            }

            Rectangle {
                width:          parent.width * 0.16
                height:         parent.height * 0.16
                radius:         ScreenTools.defaultFontPixelWidth * 0.08
                anchors.verticalCenter: parent.verticalCenter
                anchors.left:   parent.horizontalCenter
                anchors.leftMargin: ScreenTools.defaultFontPixelWidth * 0.35
                color:          "#D7E8FF"
            }
        }

        QGCLabel {
            id:                 noVideoLabel
            text:               QGroundControl.settingsManager.videoSettings.streamEnabled.rawValue ? qsTr("WAITING FOR VIDEO") : qsTr("VIDEO DISABLED")
            font.bold:          true
            color:              "#F3F7FB"
            font.pointSize:     useSmallFont ? ScreenTools.smallFontPointSize : ScreenTools.largeFontPointSize
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter:   parent.verticalCenter
            anchors.verticalCenterOffset: ScreenTools.defaultFontPixelHeight * 0.7
        }

        QGCLabel {
            text:               QGroundControl.settingsManager.videoSettings.streamEnabled.rawValue ? qsTr("Video stream is connected but no frames are available yet.") : qsTr("Enable video streaming to show the camera feed here.")
            color:              "#7F93A7"
            font.pointSize:     useSmallFont ? ScreenTools.smallFontPointSize * 0.92 : ScreenTools.defaultFontPointSize
            wrapMode:           Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            width:              Math.min(parent.width * 0.34, ScreenTools.defaultFontPixelWidth * 38)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top:        noVideoLabel.bottom
            anchors.topMargin:  ScreenTools.defaultFontPixelHeight * 0.35
        }
    }

    Rectangle {
        id:             videoBackground
        anchors.fill:   parent
        color:          "black"
        visible:        QGroundControl.videoManager.decoding
        function getWidth() {
            if(_ar != 0.0){
                if(_isMode_FIT_HEIGHT 
                        || (_isMode_FILL && (root.width/root.height < _ar))
                        || (_isMode_NO_CROP && (root.width/root.height > _ar))){
                    // This return value has different implications depending on the mode
                    // For FIT_HEIGHT and FILL
                    //    makes so the video width will be larger than (or equal to) the screen width
                    // For NO_CROP Mode
                    //    makes so the video width will be smaller than (or equal to) the screen width
                    return root.height * _ar
                }
            }
            return root.width
        }
        function getHeight() {
            if(_ar != 0.0){
                if(_isMode_FIT_WIDTH 
                        || (_isMode_FILL && (root.width/root.height > _ar)) 
                        || (_isMode_NO_CROP && (root.width/root.height < _ar))){
                    // This return value has different implications depending on the mode
                    // For FIT_WIDTH and FILL
                    //    makes so the video height will be larger than (or equal to) the screen height
                    // For NO_CROP Mode
                    //    makes so the video height will be smaller than (or equal to) the screen height
                    return root.width * (1 / _ar)
                }
            }
            return root.height
        }
        Component {
            id: videoBackgroundComponent
            QGCVideoBackground {
                id:             videoContent
                objectName:     "videoContent"

                Connections {
                    target: QGroundControl.videoManager
                    function onImageFileChanged(filename) {
                        videoContent.grabToImage(function(result) {
                            if (!result.saveToFile(filename)) {
                                console.error('Error capturing video frame');
                            }
                        });
                    }
                }

                Rectangle {
                    color:  Qt.rgba(1,1,1,0.5)
                    height: parent.height
                    width:  1
                    x:      parent.width * 0.33
                    visible: _showGrid && !QGroundControl.videoManager.fullScreen
                }
                Rectangle {
                    color:  Qt.rgba(1,1,1,0.5)
                    height: parent.height
                    width:  1
                    x:      parent.width * 0.66
                    visible: _showGrid && !QGroundControl.videoManager.fullScreen
                }
                Rectangle {
                    color:  Qt.rgba(1,1,1,0.5)
                    width:  parent.width
                    height: 1
                    y:      parent.height * 0.33
                    visible: _showGrid && !QGroundControl.videoManager.fullScreen
                }
                Rectangle {
                    color:  Qt.rgba(1,1,1,0.5)
                    width:  parent.width
                    height: 1
                    y:      parent.height * 0.66
                    visible: _showGrid && !QGroundControl.videoManager.fullScreen
                }
            }
        }
        Loader {
            // GStreamer is causing crashes on Lenovo laptop OpenGL Intel drivers. In order to workaround this
            // we don't load a QGCVideoBackground object when video is disabled. This prevents any video rendering
            // code from running. Hence the Loader to completely remove it.
            height:             parent.getHeight()
            width:              parent.getWidth()
            anchors.centerIn:   parent
            visible:            QGroundControl.videoManager.decoding
            sourceComponent:    videoBackgroundComponent

            property bool videoDisabled: QGroundControl.settingsManager.videoSettings.videoSource.rawValue === QGroundControl.settingsManager.videoSettings.disabledVideoSource
        }

        //-- Thermal Image
        Item {
            id:                 thermalItem
            width:              height * QGroundControl.videoManager.thermalAspectRatio
            height:             _camera ? (_camera.thermalMode === MavlinkCameraControl.THERMAL_FULL ? parent.height : (_camera.thermalMode === MavlinkCameraControl.THERMAL_PIP ? ScreenTools.defaultFontPixelHeight * 12 : parent.height * _thermalHeightFactor)) : 0
            anchors.centerIn:   parent
            visible:            QGroundControl.videoManager.hasThermal && _camera.thermalMode !== MavlinkCameraControl.THERMAL_OFF
            function pipOrNot() {
                if(_camera) {
                    if(_camera.thermalMode === MavlinkCameraControl.THERMAL_PIP) {
                        anchors.centerIn    = undefined
                        anchors.top         = parent.top
                        anchors.topMargin   = mainWindow.header.height + (ScreenTools.defaultFontPixelHeight * 0.5)
                        anchors.left        = parent.left
                        anchors.leftMargin  = ScreenTools.defaultFontPixelWidth * 12
                    } else {
                        anchors.top         = undefined
                        anchors.topMargin   = undefined
                        anchors.left        = undefined
                        anchors.leftMargin  = undefined
                        anchors.centerIn    = parent
                    }
                }
            }
            Connections {
                target:                 _camera
                onThermalModeChanged:   thermalItem.pipOrNot()
            }
            onVisibleChanged: {
                thermalItem.pipOrNot()
            }
            QGCVideoBackground {
                id:             thermalVideo
                objectName:     "thermalVideo"
                anchors.fill:   parent
                opacity:        _camera ? (_camera.thermalMode === MavlinkCameraControl.THERMAL_BLEND ? _camera.thermalOpacity / 100 : 1.0) : 0
            }
        }
        //-- Zoom
        PinchArea {
            id:             pinchZoom
            enabled:        _hasZoom
            anchors.fill:   parent
            onPinchStarted: pinchZoom.zoom = 0
            onPinchUpdated: {
                if(_hasZoom) {
                    var z = 0
                    if(pinch.scale < 1) {
                        z = Math.round(pinch.scale * -10)
                    } else {
                        z = Math.round(pinch.scale)
                    }
                    if(pinchZoom.zoom != z) {
                        _camera.stepZoom(z)
                    }
                }
            }
            property int zoom: 0
        }
    }
}
