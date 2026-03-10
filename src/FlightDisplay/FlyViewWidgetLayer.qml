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
import QtCore

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Controllers
import QGroundControl.FactSystem
import QGroundControl.FlightDisplay
import QGroundControl.FlightMap
import QGroundControl.Palette
import QGroundControl.ScreenTools
import QGroundControl.Vehicle

// This is the ui overlay layer for the widgets/tools for Fly View
Item {
    id: _root

    property var    parentToolInsets
    property var    totalToolInsets:        _totalToolInsets
    property var    mapControl
    property var    mapControl3D
    property bool   isViewer3DOpen:         false
    readonly property var _mapScaleControl: (isViewer3DOpen && mapControl3D) ? mapControl3D : mapControl
    readonly property var _activeViewControl: _mapScaleControl

    property var    _activeVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    property var    _planMasterController:  globals.planMasterControllerFlyView
    property var    _missionController:     _planMasterController.missionController
    property var    _geoFenceController:    _planMasterController.geoFenceController
    property var    _rallyPointController:  _planMasterController.rallyPointController
    property var    _guidedController:      globals.guidedControllerFlyView
    property real   _margins:               ScreenTools.defaultFontPixelWidth / 2
    property real   _toolsMargin:           ScreenTools.defaultFontPixelWidth * 0.75
    property real   _rightDrawerOffset:     mainWindow ? mainWindow._rightSideDrawerOffset : 0
    property rect   _centerViewport:        Qt.rect(0, 0, width, height)
    property real   _rightPanelWidth:       ScreenTools.defaultFontPixelWidth * 30
    property alias  _gripperMenu:           gripperOptions
    property real   _layoutMargin:          ScreenTools.defaultFontPixelWidth * 0.75
    property real   _layoutSpacing:         ScreenTools.defaultFontPixelWidth
    property bool   _showSingleVehicleUI:   true
    property bool   _pendingPreflightPopupOpen: false
    property bool   _showCameraControls:    true

    property bool utmspActTrigger

    QGCPalette { id: qgcPal }

    function _openPreFlightChecklist() {
        if (!QGroundControl.multiVehicleManager.activeVehicle &&
            QGroundControl.multiVehicleManager.vehicles &&
            QGroundControl.multiVehicleManager.vehicles.count > 0) {
            QGroundControl.multiVehicleManager.activeVehicle = QGroundControl.multiVehicleManager.vehicles.get(0)
        }

        if (!preFlightChecklistLoader.active) {
            _pendingPreflightPopupOpen = true
            preFlightChecklistLoader.active = true
        }
        if (preFlightChecklistLoader.item) {
            preFlightChecklistLoader.item.open()
            _pendingPreflightPopupOpen = false
        }
    }

    function openHudCustomizationPanel() {
        if (!hudCustomizationPopup.visible) {
            hudCustomizationPopup.open()
        }
    }

    function dismissViewControlsPopup() {
        if (hudCustomizationPopup.visible) {
            hudCustomizationPopup.close()
        }
    }

    function openPreFlightChecklist() {
        _openPreFlightChecklist()
    }

    function _setPanModeOnControl(control, modeKey) {
        if (control && (typeof control.setViewPanMode === "function")) {
            control.setViewPanMode(modeKey)
        }
    }

    function _applyPanModeToAllViews(modeKey) {
        _setPanModeOnControl(mapControl, modeKey)
        _setPanModeOnControl(mapControl3D, modeKey)
    }

    function _setDeclutterOnControl(control, enabled) {
        if (!control) {
            return
        }

        const currentEnabled = (control.declutterEnabled === true)
        if (currentEnabled === enabled) {
            return
        }

        if (typeof control.toggleDeclutter === "function") {
            control.toggleDeclutter()
        } else if (typeof control.setDeclutterEnabled === "function") {
            control.setDeclutterEnabled(enabled)
        }
    }

    function _toggleDeclutterAcrossViews() {
        const targetEnabled = !(_activeViewControl && _activeViewControl.declutterEnabled === true)
        _setDeclutterOnControl(mapControl, targetEnabled)
        _setDeclutterOnControl(mapControl3D, targetEnabled)
    }

    onVisibleChanged: {
        if (!visible) {
            dismissViewControlsPopup()
        }
    }

    QGCToolInsets {
        id:                     _totalToolInsets
        leftEdgeTopInset:       toolStrip.leftEdgeTopInset
        leftEdgeCenterInset:    toolStrip.leftEdgeCenterInset
        leftEdgeBottomInset:    virtualJoystickMultiTouch.visible ? virtualJoystickMultiTouch.leftEdgeBottomInset : parentToolInsets.leftEdgeBottomInset
        rightEdgeTopInset:      topRightPanel.rightEdgeTopInset
        rightEdgeCenterInset:   topRightPanel.rightEdgeCenterInset
        rightEdgeBottomInset:   bottomRightRowLayout.rightEdgeBottomInset
        topEdgeLeftInset:       toolStrip.topEdgeLeftInset
        topEdgeCenterInset:     mapScale.topEdgeCenterInset
        topEdgeRightInset:      topRightPanel.topEdgeRightInset
        bottomEdgeLeftInset:    virtualJoystickMultiTouch.visible ? virtualJoystickMultiTouch.bottomEdgeLeftInset : parentToolInsets.bottomEdgeLeftInset
        bottomEdgeCenterInset:  bottomRightRowLayout.bottomEdgeCenterInset
        bottomEdgeRightInset:   virtualJoystickMultiTouch.visible ? virtualJoystickMultiTouch.bottomEdgeRightInset : bottomRightRowLayout.bottomEdgeRightInset
    }

    FlyViewTopRightPanel {
        id:                     topRightPanel
        anchors.top:            parent.top
        anchors.right:          parent.right
        anchors.topMargin:      _layoutMargin
        anchors.rightMargin:    _layoutMargin + _rightDrawerOffset
        maximumHeight:          parent.height - (bottomRightRowLayout.height + _margins * 5)
        showCameraCard:         _showCameraControls

        property real topEdgeRightInset:    height + _layoutMargin
        property real rightEdgeTopInset:    width + _layoutMargin
        property real rightEdgeCenterInset: rightEdgeTopInset
    }

    FlyViewTopRightColumnLayout {
        id:                 topRightColumnLayout
        anchors.margins:    _layoutMargin
        anchors.top:        parent.top
        anchors.topMargin:  _layoutMargin + hudCustomizeButton.height + (ScreenTools.defaultFontPixelHeight * 0.45)
        anchors.bottom:     bottomRightRowLayout.top
        anchors.right:      parent.right
        anchors.rightMargin:_layoutMargin + _rightDrawerOffset + (topRightPanel.visible ? topRightPanel.width + (ScreenTools.defaultFontPixelWidth * 0.35) : 0)
        spacing:            _layoutSpacing
        visible:            !QGroundControl.videoManager.fullScreen
        showTerrainCard:    true
        showCameraCard:     _showCameraControls && !topRightPanel.visible
        showPreflightCard:  false
        openChecklistFn:    _openPreFlightChecklist

        property real topEdgeRightInset:    childrenRect.height + _layoutMargin
        property real rightEdgeTopInset:    width + _layoutMargin
        property real rightEdgeCenterInset: rightEdgeTopInset
    }

    FlyViewBottomRightRowLayout {
        id:                 bottomRightRowLayout
        anchors.margins:    _layoutMargin
        anchors.bottom:     parent.bottom
        anchors.right:      parent.right
        anchors.rightMargin:_layoutMargin
        z:                  QGroundControl.zOrderWidgets + 1
        spacing:            _layoutSpacing
        property real bottomEdgeRightInset:     height + _layoutMargin
        property real bottomEdgeCenterInset:    bottomEdgeRightInset
        property real rightEdgeBottomInset:     width + _layoutMargin
    }

    Rectangle {
        id:                     hudCustomizeButton
        anchors.top:            parent.top
        anchors.right:          parent.right
        anchors.topMargin:      _layoutMargin
        anchors.rightMargin:    _layoutMargin + _rightDrawerOffset + (topRightPanel.visible ? topRightPanel.width + (ScreenTools.defaultFontPixelWidth * 0.35) : 0)
        width:                  ScreenTools.defaultFontPixelHeight * 2.15
        height:                 width
        radius:                 ScreenTools.buttonBorderRadius
        color:                  qgcPal.button
        border.width:           1
        border.color:           qgcPal.groupBorder
        z:                      QGroundControl.zOrderWidgets + 1
        visible:                !QGroundControl.videoManager.fullScreen
        antialiasing:           true

        QGCColoredImage {
            anchors.centerIn:       parent
            width:                  parent.width * 0.54
            height:                 width
            sourceSize.height:      height
            source:                 "/qmlimages/Gears.svg"
            fillMode:               Image.PreserveAspectFit
            color:                  qgcPal.buttonText
        }

        MouseArea {
            anchors.fill:   parent
            hoverEnabled:   !ScreenTools.isMobile
            onClicked: {
                if (hudCustomizationPopup.visible) {
                    hudCustomizationPopup.close()
                } else {
                    hudCustomizationPopup.open()
                }
            }
        }
    }

    Item {
        id:                     hudPopupDismissLayer
        anchors.fill:           parent
        z:                      hudCustomizeButton.z + 1
        visible:                hudCustomizationPopup.visible

        MouseArea {
            anchors.fill: parent

            onPressed: {
                var insidePopup = mouse.x >= hudCustomizationPopup.x &&
                                  mouse.x <= (hudCustomizationPopup.x + hudCustomizationPopup.width) &&
                                  mouse.y >= hudCustomizationPopup.y &&
                                  mouse.y <= (hudCustomizationPopup.y + hudCustomizationPopup.height)
                if (insidePopup) {
                    mouse.accepted = false
                } else {
                    hudCustomizationPopup.close()
                    mouse.accepted = true
                }
            }
        }
    }

    Popup {
        id:                     hudCustomizationPopup
        x:                      Math.max(ScreenTools.defaultFontPixelWidth, hudCustomizeButton.x - width + hudCustomizeButton.width)
        y:                      hudCustomizeButton.y + hudCustomizeButton.height + (ScreenTools.defaultFontPixelHeight * 0.4)
        width:                  ScreenTools.defaultFontPixelWidth * 29
        modal:                  false
        focus:                  true
        closePolicy:            Popup.CloseOnEscape
        padding:                ScreenTools.defaultFontPixelHeight * 0.8

        background: Rectangle {
            color:          qgcPal.window
            radius:         ScreenTools.panelCornerRadius
            border.width:   1
            border.color:   qgcPal.groupBorder
            opacity:        0.96
        }

        contentItem: ColumnLayout {
            spacing: ScreenTools.defaultDialogControlSpacing

            QGCLabel {
                text:           qsTr("View Controls")
                font.pointSize: ScreenTools.mediumFontPointSize
                font.weight:    Font.DemiBold
            }

            Rectangle {
                id:                     panModeSelector
                Layout.fillWidth:       true
                Layout.preferredHeight: ScreenTools.implicitButtonHeight
                radius:                 ScreenTools.buttonBorderRadius
                color:                  qgcPal.button
                border.width:           1
                border.color:           qgcPal.groupBorder
                clip:                   true
                enabled:                _activeViewControl && (typeof _activeViewControl.setViewPanMode === "function")
                opacity:                enabled ? 1 : 0.6

                property var modeOptions: [
                    { modeKey: "free",   text: qsTr("Free Pan"),  iconSource: "/qmlimages/MapType.svg" },
                    { modeKey: "auto",   text: qsTr("Auto Pan"),  iconSource: "/qmlimages/TrackingIcon.svg" },
                    { modeKey: "follow", text: qsTr("Following"), iconSource: "/qmlimages/MapCenter.svg" }
                ]

                Repeater {
                    id: panModeRepeater
                    model: panModeSelector.modeOptions

                    delegate: Rectangle {
                        width:      panModeSelector.width / panModeRepeater.count
                        height:     panModeSelector.height
                        x:          index * width
                        color:      (_activeViewControl && _activeViewControl.viewPanMode === modelData.modeKey) ? qgcPal.buttonHighlight : qgcPal.button
                        border.width: index < (panModeRepeater.count - 1) ? 1 : 0
                        border.color: qgcPal.groupBorder

                        QGCColoredImage {
                            anchors.centerIn:   parent
                            width:              ScreenTools.defaultFontPixelHeight * 1.05
                            height:             width
                            sourceSize.height:  height
                            source:             modelData.iconSource
                            fillMode:           Image.PreserveAspectFit
                            color:              (_activeViewControl && _activeViewControl.viewPanMode === modelData.modeKey) ? qgcPal.buttonHighlightText : qgcPal.buttonText
                        }

                        MouseArea {
                            id:             modeButtonArea
                            anchors.fill:   parent
                            enabled:        panModeSelector.enabled
                            hoverEnabled:   !ScreenTools.isMobile
                            onClicked: {
                                _applyPanModeToAllViews(modelData.modeKey)
                                dismissViewControlsPopup()
                            }
                        }

                        ToolTip.visible: modeButtonArea.containsMouse && !ScreenTools.isMobile
                        ToolTip.text: modelData.text
                    }
                }
            }

            QGCButton {
                Layout.fillWidth:   true
                text:               (_activeViewControl && _activeViewControl.declutterEnabled) ? qsTr("Declutter On") : qsTr("Declutter Off")
                enabled:            _activeViewControl && (typeof _activeViewControl.toggleDeclutter === "function")
                onClicked: {
                    _toggleDeclutterAcrossViews()
                    dismissViewControlsPopup()
                }
            }

            QGCButton {
                Layout.fillWidth:   true
                text:               _showCameraControls ? qsTr("Camera Controls On") : qsTr("Camera Controls Off")
                onClicked: {
                    _showCameraControls = !_showCameraControls
                    dismissViewControlsPopup()
                }
            }

            QGCButton {
                Layout.fillWidth:   true
                text:               qsTr("Center Vehicle")
                enabled:            _activeViewControl &&
                                    _activeViewControl.canCenterVehicle &&
                                    (typeof _activeViewControl.centerOnActiveVehicle === "function")
                onClicked: {
                    if (_activeViewControl && (typeof _activeViewControl.centerOnActiveVehicle === "function")) {
                        _activeViewControl.centerOnActiveVehicle()
                    }
                    dismissViewControlsPopup()
                }
            }
        }
    }

    FlyViewMissionCompleteDialog {
        planMasterController:   _planMasterController
        missionController:      _missionController
        geoFenceController:     _geoFenceController
        rallyPointController:   _rallyPointController
    }

    GuidedActionConfirm {
        anchors.margins:            _toolsMargin
        anchors.top:                parent.top
        anchors.horizontalCenter:   parent.horizontalCenter
        z:                          QGroundControl.zOrderTopMost
        guidedController:           _guidedController
        guidedValueSlider:          _guidedValueSlider
        utmspSliderTrigger:         utmspActTrigger
    }

    //-- Virtual Joystick
    Loader {
        id:                         virtualJoystickMultiTouch
        z:                          QGroundControl.zOrderTopMost + 1
        anchors.right:              parent.right
        anchors.rightMargin:        anchors.leftMargin
        height:                     Math.min(parent.height * 0.25, ScreenTools.defaultFontPixelWidth * 16)
        visible:                    _virtualJoystickEnabled && !QGroundControl.videoManager.fullScreen && !(_activeVehicle ? _activeVehicle.usingHighLatencyLink : false)
        anchors.bottom:             parent.bottom
        anchors.bottomMargin:       bottomLoaderMargin
        anchors.left:               parent.left   
        anchors.leftMargin:         ( y > toolStrip.y + toolStrip.height ? toolStrip.width / 2 : toolStrip.width * 1.05 + toolStrip.x) 
        source:                     "qrc:/qml/QGroundControl/FlightDisplay/VirtualJoystick.qml"
        active:                     _virtualJoystickEnabled && !(_activeVehicle ? _activeVehicle.usingHighLatencyLink : false)

        property real bottomEdgeLeftInset:     parent.height-y
        property bool autoCenterThrottle:      QGroundControl.settingsManager.appSettings.virtualJoystickAutoCenterThrottle.rawValue
        property bool leftHandedMode:          QGroundControl.settingsManager.appSettings.virtualJoystickLeftHandedMode.rawValue
        property bool _virtualJoystickEnabled: QGroundControl.settingsManager.appSettings.virtualJoystick.rawValue
        property real bottomEdgeRightInset:    parent.height-y
        property var  _pipViewMargin:          _pipView.visible ? parentToolInsets.bottomEdgeLeftInset + ScreenTools.defaultFontPixelHeight * 2 : 
                                               bottomRightRowLayout.height + ScreenTools.defaultFontPixelHeight * 1.5

        property var  bottomLoaderMargin:      _pipViewMargin >= parent.height / 2 ? parent.height / 2 : _pipViewMargin

        // Width is difficult to access directly hence this hack which may not work in all circumstances
        property real leftEdgeBottomInset:  visible ? bottomEdgeLeftInset + width/18 - ScreenTools.defaultFontPixelHeight*2 : 0
        property real rightEdgeBottomInset: visible ? bottomEdgeRightInset + width/18 - ScreenTools.defaultFontPixelHeight*2 : 0
        property real rootWidth:            _root.width
        property var  itemX:                virtualJoystickMultiTouch.x   // real X on screen

        onRootWidthChanged: virtualJoystickMultiTouch.status == Loader.Ready && visible ? virtualJoystickMultiTouch.item.uiTotalWidth = rootWidth : undefined
        onItemXChanged:     virtualJoystickMultiTouch.status == Loader.Ready && visible ? virtualJoystickMultiTouch.item.uiRealX = itemX : undefined

        //Loader status logic
        onLoaded: {
            if (virtualJoystickMultiTouch.visible) {
                virtualJoystickMultiTouch.item.calibration = true 
                virtualJoystickMultiTouch.item.uiTotalWidth = rootWidth
                virtualJoystickMultiTouch.item.uiRealX = itemX
            } else {
                virtualJoystickMultiTouch.item.calibration = false
            }
        }
    }

    FlyViewToolStrip {
        id:                     toolStrip
        anchors.leftMargin:     _toolsMargin + parentToolInsets.leftEdgeCenterInset
        anchors.topMargin:      _toolsMargin + parentToolInsets.topEdgeLeftInset
        anchors.left:           parent.left
        anchors.top:            parent.top
        z:                      QGroundControl.zOrderWidgets
        maxHeight:              parent.height - y - parentToolInsets.bottomEdgeLeftInset - _toolsMargin
        visible:                !QGroundControl.videoManager.fullScreen

        onDisplayPreFlightChecklist: {
            _openPreFlightChecklist()
        }

        property real topEdgeLeftInset:     visible ? y + height : 0
        property real leftEdgeTopInset:     visible ? x + width : 0
        property real leftEdgeCenterInset:  leftEdgeTopInset
    }

    GripperMenu {
        id: gripperOptions
    }

    VehicleWarnings {
        anchors.centerIn:   parent
        z:                  QGroundControl.zOrderTopMost
    }

    MapScale {
        id:                 mapScale
        anchors.margins:    _toolsMargin
        anchors.left:       toolStrip.right
        anchors.top:        parent.top
        mapControl:         _mapScaleControl
        buttonsOnLeft:      true
        visible:            !ScreenTools.isTinyScreen &&
                            QGroundControl.corePlugin.options.flyView.showMapScale &&
                            _mapScaleControl &&
                            _mapScaleControl.pipState &&
                            _mapScaleControl.pipState.state === _mapScaleControl.pipState.fullState

        property real topEdgeCenterInset: visible ? y + height : 0
    }

    Loader {
        id: preFlightChecklistLoader
        sourceComponent: preFlightChecklistPopup
        active: true
        onLoaded: {
            if (_pendingPreflightPopupOpen && item) {
                item.open()
                _pendingPreflightPopupOpen = false
            }
        }
    }

    Component {
        id: preFlightChecklistPopup
        FlyViewPreFlightChecklistPopup {
        }
    }
}
