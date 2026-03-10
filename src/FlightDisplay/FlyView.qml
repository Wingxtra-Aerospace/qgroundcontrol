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
import QtQuick.Dialogs
import QtQuick.Layouts

import QtLocation
import QtPositioning
import QtQuick.Window
import QtQml.Models

import QGroundControl
import QGroundControl.Controllers
import QGroundControl.Controls
import QGroundControl.FactSystem
import QGroundControl.FlightDisplay
import QGroundControl.FlightMap
import QGroundControl.Palette
import QGroundControl.ScreenTools
import QGroundControl.Vehicle

// 3D Viewer modules
import Viewer3D

Item {
    id: _root

    // These should only be used by MainRootWindow
    property var planController:    _planController
    property var guidedController:  _guidedController

    // Properties of UTM adapter
    property bool utmspSendActTrigger: false

    PlanMasterController {
        id:                     _planController
        flyView:                true
        Component.onCompleted:  start()
    }

    property bool   _mainWindowIsMap:       mapControl.pipState.state === mapControl.pipState.fullState
    property bool   _isFullWindowItemDark:  _mainWindowIsMap ? mapControl.isSatelliteMap : true
    property var    _activeVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    property var    _missionController:     _planController.missionController
    property var    _geoFenceController:    _planController.geoFenceController
    property var    _rallyPointController:  _planController.rallyPointController
    property real   _margins:               ScreenTools.defaultFontPixelWidth / 2
    property var    _guidedController:      guidedActionsController
    property var    _guidedValueSlider:     guidedValueSlider
    property var    _widgetLayer:           widgetLayer
    property real   _toolsMargin:           ScreenTools.defaultFontPixelWidth * 0.75
    property rect   _centerViewport:        Qt.rect(0, 0, width, height)
    property real   _rightPanelWidth:       ScreenTools.defaultFontPixelWidth * 30
    property var    _mapControl:            mapControl
    property bool   _showVideoWidget:       false
    readonly property int _paramUiHidden:       0
    readonly property int _paramUiLoading:      1
    readonly property int _paramUiSuccess:      2
    readonly property int _paramUiFailed:       3
    property int _paramUiState:                 _paramUiHidden
    property bool _paramFetchSessionActive:     false
    property real _normalizedParamFetchProgress:_activeVehicle ? Math.max(0.0, Math.min(1.0, _activeVehicle.loadProgress)) : 0

    property real   _fullItemZorder:    0
    property real   _pipItemZorder:     QGroundControl.zOrderWidgets

    function _calcCenterViewPort() {
        var newToolInset = Qt.rect(0, 0, width, height)
        toolstrip.adjustToolInset(newToolInset)
    }

    function dropMainStatusIndicatorTool() {
        toolbar.dropMainStatusIndicatorTool();
    }

    function dismissViewControlsPopup() {
        if (widgetLayer && (typeof widgetLayer.dismissViewControlsPopup === "function")) {
            widgetLayer.dismissViewControlsPopup()
        }
    }

    QGCToolInsets {
        id:                     _toolInsets
        leftEdgeBottomInset:    _pipView.leftEdgeBottomInset
        bottomEdgeLeftInset:    _pipView.bottomEdgeLeftInset
    }

    FlyViewToolBar {
        id:         toolbar
        visible:    !QGroundControl.videoManager.fullScreen
    }

    QGCPalette {
        id: flyProgressPal
    }

    function _paramFetchMissing() {
        return !!(_activeVehicle && _activeVehicle.parameterManager && _activeVehicle.parameterManager.missingParameters)
    }

    function _beginParamFetchSession() {
        if (!_activeVehicle || _activeVehicle.initialConnectComplete) {
            return
        }
        _paramFetchSessionActive = true
        _paramUiState = _paramUiLoading
        paramFetchHideTimer.stop()
    }

    function _finalizeParamFetchSession() {
        if (!_paramFetchSessionActive) {
            return
        }
        _paramUiState = _paramFetchMissing() ? _paramUiFailed : _paramUiSuccess
        paramFetchHideTimer.restart()
    }

    function _resetParamFetchUi() {
        _paramUiState = _paramUiHidden
        _paramFetchSessionActive = false
        paramFetchHideTimer.stop()
    }

    function _syncParamFetchUiFromActiveVehicle() {
        _resetParamFetchUi()
        if (_activeVehicle && !_activeVehicle.initialConnectComplete) {
            _beginParamFetchSession()
        }
    }

    Item {
        id:                 mapHolder
        anchors.top:        toolbar.bottom
        anchors.bottom:     parent.bottom
        anchors.left:       parent.left
        anchors.right:      parent.right

        Rectangle {
            id:                     parameterFetchBar
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top:            parent.top
            anchors.topMargin:      ScreenTools.defaultFontPixelHeight * 0.22
            width:                  Math.min(parent.width * 0.42, ScreenTools.defaultFontPixelWidth * 54)
            height:                 ScreenTools.defaultFontPixelHeight * 1.15
            radius:                 height * 0.5
            color:                  Qt.rgba(0, 0, 0, 0.34)
            border.width:           1
            border.color:           Qt.rgba(1, 1, 1, 0.20)
            visible:                toolbar.visible && _paramUiState !== _paramUiHidden
            opacity:                visible ? 1 : 0
            clip:                   true
            z:                      QGroundControl.zOrderWidgets + 2

            property color _stateColor: _paramUiState === _paramUiLoading
                ? flyProgressPal.colorBlue
                : (_paramUiState === _paramUiFailed ? flyProgressPal.colorRed : flyProgressPal.colorGreen)
            property string _statusText: _paramUiState === _paramUiLoading
                ? qsTr("Fetching parameters %1%").arg(Math.round(_normalizedParamFetchProgress * 100))
                : (_paramUiState === _paramUiSuccess ? qsTr("Parameter fetch complete") : qsTr("Parameter fetch incomplete"))

            Behavior on opacity {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.InOutQuad
                }
            }

            Rectangle {
                anchors.left:       parent.left
                anchors.top:        parent.top
                anchors.bottom:     parent.bottom
                radius:             parameterFetchBar.radius
                color:              parameterFetchBar._stateColor
                opacity:            _paramUiState === _paramUiLoading ? 0.68 : 0.92
                width:              _paramUiState === _paramUiLoading
                                        ? Math.max(0, parameterFetchBar.width * _normalizedParamFetchProgress)
                                        : (_paramUiState === _paramUiHidden ? 0 : parameterFetchBar.width)

                Behavior on width {
                    NumberAnimation {
                        duration: 130
                        easing.type: Easing.OutCubic
                    }
                }
            }

            QGCLabel {
                anchors.centerIn:   parent
                text:               parameterFetchBar._statusText
                font.pointSize:     ScreenTools.smallFontPointSize * 1.05
                font.weight:        Font.DemiBold
                color:              flyProgressPal.buttonHighlightText
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment:  Text.AlignVCenter
            }
        }

        FlyViewMap {
            id:                     mapControl
            planMasterController:   _planController
            rightPanelWidth:        ScreenTools.defaultFontPixelHeight * 9
            pipView:                _pipView
            pipMode:                !_mainWindowIsMap
            toolInsets:             customOverlay.totalToolInsets
            mapName:                "FlightDisplayView"
            enabled:                !viewer3DWindow.isOpen
            visible:                !viewer3DWindow.isOpen
        }

        FlyViewVideo {
            id:         videoControl
            pipView:    _pipView
        }

        PipView {
            id:                     _pipView
            anchors.left:           parent.left
            anchors.bottom:         parent.bottom
            anchors.margins:        _toolsMargin
            item1IsFullSettingsKey: "MainFlyWindowIsMap"
            item1:                  viewer3DWindow.isOpen ? viewer3DWindow : mapControl
            item2:                  QGroundControl.videoManager.hasVideo ? videoControl : null
            show:                   QGroundControl.videoManager.hasVideo && !QGroundControl.videoManager.fullScreen &&
                                        _showVideoWidget &&
                                        (videoControl.pipState.state === videoControl.pipState.pipState ||
                                         mapControl.pipState.state === mapControl.pipState.pipState ||
                                         viewer3DWindow.pipState.state === viewer3DWindow.pipState.pipState)
            z:                      QGroundControl.zOrderWidgets

            property real leftEdgeBottomInset: visible ? width + anchors.margins : 0
            property real bottomEdgeLeftInset: visible ? height + anchors.margins : 0
        }

        Rectangle {
            id:                     openVideoButton
            width:                  ScreenTools.defaultFontPixelHeight * 3.0
            height:                 width
            radius:                 ScreenTools.defaultFontPixelHeight * 0.48
            color:                  openVideoButton._pressed ? Qt.rgba(0.08, 0.13, 0.20, 0.92) :
                                    (openVideoButton._hovered ? Qt.rgba(0.12, 0.18, 0.28, 0.86) : Qt.rgba(0.05, 0.10, 0.18, 0.82))
            border.width:           openVideoButton._hovered ? 1.4 : 1.0
            border.color:           openVideoButton._hovered ? "#B3DDF6FF" : "#7AB9DAF2"
            anchors.left:           parent.left
            anchors.bottom:         parent.bottom
            anchors.margins:        _toolsMargin
            visible:                QGroundControl.videoManager.hasVideo &&
                                    !QGroundControl.videoManager.fullScreen &&
                                    (_iconShown || opacity > 0.01)
            z:                      QGroundControl.zOrderWidgets + 1
            opacity:                _iconShown ? 1 : 0
            scale:                  _iconShown ? (openVideoButton._pressed ? 0.96 : (openVideoButton._hovered ? 1.03 : 1.0)) : 0.88
            transformOrigin:        Item.Center

            property bool _iconShown: QGroundControl.videoManager.hasVideo &&
                                      !QGroundControl.videoManager.fullScreen &&
                                      !_showVideoWidget
            property bool _hovered: openVideoMouseArea.containsMouse && !ScreenTools.isMobile
            property bool _pressed: openVideoMouseArea.pressed

            Rectangle {
                anchors.fill:       parent
                anchors.margins:    -2
                radius:             openVideoButton.radius + 2
                color:              "transparent"
                border.width:       openVideoButton._hovered ? 1.2 : 0.8
                border.color:       openVideoButton._hovered ? "#4472C1FF" : "#2C5B88CC"
                opacity:            openVideoButton._iconShown ? 0.9 : 0
            }

            Rectangle {
                anchors.fill:       parent
                anchors.margins:    1
                radius:             Math.max(2, openVideoButton.radius - 1)
                color:              "transparent"
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "#35FFFFFF" }
                    GradientStop { position: 0.5; color: "#12FFFFFF" }
                    GradientStop { position: 1.0; color: "#00000000" }
                }
                opacity:            openVideoButton._iconShown ? 1 : 0
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: openVideoButton._iconShown ? 45 : 180
                    easing.type: Easing.InOutQuad
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: openVideoButton._iconShown ? 45 : 180
                    easing.type: Easing.OutCubic
                }
            }

            QGCColoredImage {
                anchors.centerIn:       parent
                width:                  parent.width * 0.56
                height:                 width
                sourceSize.height:      height
                source:                 "/qmlimages/camera_video.svg"
                fillMode:               Image.PreserveAspectFit
                color:                  openVideoButton._hovered ? "#F4FBFF" : "#E8F4FF"
            }

            MouseArea {
                id:             openVideoMouseArea
                anchors.fill: parent
                enabled: openVideoButton._iconShown
                hoverEnabled:   !ScreenTools.isMobile
                onClicked: {
                    _showVideoWidget = true
                    _pipView._setPipIsExpanded(true)
                }
            }
        }

        FlyViewWidgetLayer {
            id:                     widgetLayer
            anchors.top:            parent.top
            anchors.bottom:         parent.bottom
            anchors.left:           parent.left
            anchors.right:          guidedValueSlider.visible ? guidedValueSlider.left : parent.right
            z:                      _fullItemZorder + 2 // we need to add one extra layer for map 3d viewer (normally was 1)
            parentToolInsets:       _toolInsets
            mapControl:             _mapControl
            mapControl3D:           viewer3DWindow
            visible:                !QGroundControl.videoManager.fullScreen && _root.visible
            utmspActTrigger:        utmspSendActTrigger
            isViewer3DOpen:         viewer3DWindow.isOpen
        }

        FlyViewCustomLayer {
            id:                 customOverlay
            anchors.fill:       widgetLayer
            z:                  _fullItemZorder + 2
            parentToolInsets:   widgetLayer.totalToolInsets
            mapControl:         _mapControl
            visible:            !QGroundControl.videoManager.fullScreen && _root.visible
        }

        // Development tool for visualizing the insets for a paticular layer, show if needed
        FlyViewInsetViewer {
            id:                     widgetLayerInsetViewer
            anchors.top:            parent.top
            anchors.bottom:         parent.bottom
            anchors.left:           parent.left
            anchors.right:          guidedValueSlider.visible ? guidedValueSlider.left : parent.right
            z:                      widgetLayer.z + 1
            insetsToView:           widgetLayer.totalToolInsets
            visible:                false
        }

        GuidedActionsController {
            id:                 guidedActionsController
            missionController:  _missionController
            guidedValueSlider:     _guidedValueSlider
        }

        //-- Guided value slider (e.g. altitude)
        GuidedValueSlider {
            id:                 guidedValueSlider
            anchors.right:      parent.right
            anchors.top:        parent.top
            anchors.bottom:     parent.bottom
            z:                  QGroundControl.zOrderTopMost
            visible:            false
        }

        Viewer3D{
            id:                     viewer3DWindow
            anchors.fill:           parent
            z:                      _fullItemZorder + 1
            pipView:                _pipView
            missionController:      _missionController
        }

        Connections {
            target: _pipView

            function on_IsExpandedChanged() {
                if (!QGroundControl.videoManager.hasVideo) {
                    return
                }
                _showVideoWidget = _pipView._isExpanded
            }
        }

        Connections {
            target: QGroundControl.videoManager

            function onHasVideoChanged() {
                if (!QGroundControl.videoManager.hasVideo) {
                    _showVideoWidget = false
                }
            }
        }
    }

    Connections {
        target: _activeVehicle

        function onLoadProgressChanged() {
            if (!_activeVehicle) {
                _resetParamFetchUi()
                return
            }

            if (!_activeVehicle.initialConnectComplete) {
                _beginParamFetchSession()
            } else {
                _finalizeParamFetchSession()
            }
        }

        function onInitialConnectComplete() {
            _finalizeParamFetchSession()
        }
    }

    Connections {
        target: _activeVehicle && _activeVehicle.parameterManager ? _activeVehicle.parameterManager : null

        function onMissingParametersChanged() {
            if (_activeVehicle && _activeVehicle.initialConnectComplete && _paramFetchSessionActive) {
                _finalizeParamFetchSession()
            }
        }
    }

    Timer {
        id:             paramFetchHideTimer
        interval:       3200
        onTriggered: {
            _paramUiState = _paramUiHidden
            _paramFetchSessionActive = false
        }
    }

    on_ActiveVehicleChanged: _syncParamFetchUiFromActiveVehicle()

    Component.onCompleted: _syncParamFetchUiFromActiveVehicle()
}
