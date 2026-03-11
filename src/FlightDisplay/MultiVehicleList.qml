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
import QGroundControl.ScreenTools
import QGroundControl.Controls
import QGroundControl.Palette
import QGroundControl.Vehicle
import QGroundControl.FlightMap
import QGroundControl.FlightDisplay

Item {
    property real   _margin:              ScreenTools.defaultFontPixelWidth / 2
    property real   _widgetHeight:        ScreenTools.defaultFontPixelHeight * 2.5
    property var    _guidedController:    globals.guidedControllerFlyView
    property var    _activeVehicleColor:  "green"
    property var    _activeVehicle:       QGroundControl.multiVehicleManager.activeVehicle
    property var    selectedVehicles:     QGroundControl.multiVehicleManager.selectedVehicles

    implicitHeight: vehicleList.contentHeight

    function _healthLevelColor(level) {
        switch (level) {
        case "good":
            return qgcPal.colorGreen
        case "warn":
            return qgcPal.colorOrange
        case "bad":
            return qgcPal.colorRed
        default:
            return qgcPal.colorGrey
        }
    }

    function _healthLevelBackground(level) {
        switch (level) {
        case "good":
            return Qt.rgba(0.10, 0.30, 0.14, 0.55)
        case "warn":
            return Qt.rgba(0.35, 0.23, 0.04, 0.55)
        case "bad":
            return Qt.rgba(0.34, 0.10, 0.10, 0.55)
        default:
            return Qt.rgba(0.08, 0.12, 0.18, 0.55)
        }
    }

    function armAvailable() {
        for (var i = 0; i < selectedVehicles.count; i++) {
            var vehicle = selectedVehicles.get(i)
            if (vehicle.armed === false) {
                return true
            }
        }
        return false
    }


    function disarmAvailable() {
        for (var i = 0; i < selectedVehicles.count; i++) {
            var vehicle = selectedVehicles.get(i)
            if (vehicle.armed === true) {
                return true
            }
        }
        return false
    }

    function startAvailable() {
        for (var i = 0; i < selectedVehicles.count; i++) {
            var vehicle = selectedVehicles.get(i)
            if (vehicle.armed === true && vehicle.flightMode !== vehicle.missionFlightMode){
                return true
            }
        }
        return false
    }

    function pauseAvailable() {
        for (var i = 0; i < selectedVehicles.count; i++) {
            var vehicle = selectedVehicles.get(i)
            if (vehicle.armed === true && vehicle.pauseVehicleSupported) {
                return true
            }
        }
        return false
    }

    function selectVehicle(vehicleId) {
        QGroundControl.multiVehicleManager.selectVehicle(vehicleId)
    }

    function deselectVehicle(vehicleId) {
        QGroundControl.multiVehicleManager.deselectVehicle(vehicleId)
    }

    function toggleSelect(vehicleId) {
        var vehicle = QGroundControl.multiVehicleManager.getVehicleById(vehicleId)
        if (!vehicle) {
            return
        }

        var wasSelected = vehicleSelected(vehicleId)

        if (!wasSelected) {
            QGroundControl.multiVehicleManager.activeVehicle = vehicle
            selectVehicle(vehicleId)
            return
        }

        deselectVehicle(vehicleId)

        var activeVehicle = QGroundControl.multiVehicleManager.activeVehicle
        if (activeVehicle && activeVehicle.id === vehicleId) {
            if (selectedVehicles.count > 0) {
                QGroundControl.multiVehicleManager.activeVehicle = selectedVehicles.get(selectedVehicles.count - 1)
                return
            }

            var vehicles = QGroundControl.multiVehicleManager.vehicles
            for (var i = 0; i < vehicles.count; i++) {
                var candidate = vehicles.get(i)
                if (candidate && candidate.id !== vehicleId) {
                    QGroundControl.multiVehicleManager.activeVehicle = candidate
                    return
                }
            }
        }
    }

    function selectAll() {
        var vehicles = QGroundControl.multiVehicleManager.vehicles
        for (var i = 0; i < vehicles.count; i++) {
            var vehicle = vehicles.get(i)
            var vehicleId = vehicle.id
            if (!vehicleSelected(vehicleId)) {
                selectVehicle(vehicleId)
            }
        }
    }

    function deselectAll() {
        QGroundControl.multiVehicleManager.deselectAllVehicles()
    }

    function focusVehicle(vehicleId) {
        var vehicle = QGroundControl.multiVehicleManager.getVehicleById(vehicleId)
        if (!vehicle) {
            return
        }

        if (!vehicleSelected(vehicleId)) {
            selectVehicle(vehicleId)
        }
        QGroundControl.multiVehicleManager.activeVehicle = vehicle
    }

    function focusSelectedVehicleByOffset(offset) {
        if (!selectedVehicles || selectedVehicles.count <= 0) {
            return
        }

        var activeVehicle = QGroundControl.multiVehicleManager.activeVehicle
        var activeIndex = -1
        for (var i = 0; i < selectedVehicles.count; i++) {
            var selectedVehicle = selectedVehicles.get(i)
            if (selectedVehicle && activeVehicle && selectedVehicle.id === activeVehicle.id) {
                activeIndex = i
                break
            }
        }

        var step = Number(offset)
        if (!isFinite(step) || step === 0) {
            step = 1
        }

        var baseIndex = activeIndex >= 0 ? activeIndex : 0
        var nextIndex = (baseIndex + step) % selectedVehicles.count
        if (nextIndex < 0) {
            nextIndex += selectedVehicles.count
        }

        var targetVehicle = selectedVehicles.get(nextIndex)
        if (!targetVehicle) {
            return
        }
        focusVehicle(targetVehicle.id)
    }

    function vehicleSelected(vehicleId) {
        for (var i = 0; i < selectedVehicles.count; i++ ) {
            var selectedVehicle = selectedVehicles.get(i)
            if (!selectedVehicle) {
                continue
            }
            var currentId = selectedVehicle.id
            if (vehicleId === currentId) {
                return true
            }
        }
        return false
    }

    Shortcut {
        sequence: "Ctrl+]"
        context: Qt.ApplicationShortcut
        enabled: visible
        onActivated: focusSelectedVehicleByOffset(1)
    }

    Shortcut {
        sequence: "Ctrl+["
        context: Qt.ApplicationShortcut
        enabled: visible
        onActivated: focusSelectedVehicleByOffset(-1)
    }

    QGCListView {
        id:                 vehicleList
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.top:        parent.top
        anchors.bottom:     parent.bottom
        spacing:            ScreenTools.defaultFontPixelHeight / 2
        orientation:        ListView.Vertical
        model:              QGroundControl.multiVehicleManager.vehicles
        cacheBuffer:        _cacheBuffer < 0 ? 0 : _cacheBuffer
        clip:               true

        property real _cacheBuffer:     height * 2

        delegate: Rectangle {
            width:          vehicleList.width
            height:         innerColumn.height + _margin * 2
            color:          QGroundControl.multiVehicleManager.activeVehicle == _vehicle ? _activeVehicleColor : qgcPal.button
            radius:         _margin
            border.width:   _vehicle && vehicleSelected(_vehicle.id) ? 2 : 0
            border.color:   qgcPal.text

            property var    _vehicle:   object
            readonly property real _gpsLockRaw: (_vehicle && _vehicle.gps && _vehicle.gps.lock) ? Number(_vehicle.gps.lock.rawValue) : Number.NaN
            readonly property real _gpsSatCount: (_vehicle && _vehicle.gps && _vehicle.gps.count) ? Number(_vehicle.gps.count.rawValue) : Number.NaN
            readonly property bool _requiresGpsFix: _vehicle ? (_vehicle.requiresGpsFix === true) : false
            readonly property string _gpsHealthLevel: (!_requiresGpsFix || (_gpsLockRaw >= 3 && _gpsSatCount >= 6))
                ? "good"
                : ((_gpsLockRaw >= 2 && _gpsSatCount >= 4) ? "warn" : "bad")
            readonly property string _gpsHealthText: !_requiresGpsFix
                ? qsTr("GPS N/A")
                : (
                    (isFinite(_gpsSatCount) ? String(Math.round(_gpsSatCount)) : "--") +
                    " | " +
                    ((_gpsLockRaw >= 3) ? qsTr("3D+") : ((_gpsLockRaw >= 2) ? qsTr("2D") : qsTr("NO FIX")))
                )
            readonly property bool _altitudeValid: !!(_vehicle &&
                                                      _vehicle.coordinate &&
                                                      _vehicle.coordinate.isValid &&
                                                      _vehicle.altitudeRelative &&
                                                      isFinite(Number(_vehicle.altitudeRelative.rawValue)))
            readonly property string _altitudeHealthLevel: _altitudeValid ? "good" : "bad"
            readonly property string _altitudeHealthText: _altitudeValid
                ? qsTr("ALT OK")
                : qsTr("ALT --")
            readonly property real _mavlinkLossPercent: _vehicle ? Number(_vehicle.mavlinkLossPercent) : Number.NaN
            readonly property string _linkHealthLevel: !isFinite(_mavlinkLossPercent)
                ? "unknown"
                : ((_mavlinkLossPercent <= 5.0) ? "good" : ((_mavlinkLossPercent <= 15.0) ? "warn" : "bad"))
            readonly property string _linkHealthText: !isFinite(_mavlinkLossPercent)
                ? qsTr("LINK --")
                : qsTr("LOSS %1%").arg(_mavlinkLossPercent.toFixed(1))

            QGCMouseArea {
                anchors.fill:       parent
                onClicked:          toggleSelect(_vehicle.id)
                onDoubleClicked:    focusVehicle(_vehicle.id)
            }

            Column {
                id:                         innerColumn
                anchors.centerIn:           parent
                spacing:                    _margin

                RowLayout {
                    anchors.horizontalCenter:   parent.horizontalCenter
                    anchors.margins:    _margin
                    spacing:            _margin

                    IntegratedCompassAttitude {
                        id: compassWidget
                        compassRadius:              _widgetHeight / 2 - attitudeSize / 2
                        compassBorder:              0
                        attitudeSize:               ScreenTools.defaultFontPixelWidth / 2
                        attitudeSpacing:            attitudeSize / 2
                        usedByMultipleVehicleList:   true
                        vehicle:                     _vehicle
                    }

                    QGCLabel {
                        text: " | "
                        font.pointSize:       ScreenTools.largeFontPointSize
                        color:                qgcPal.text
                        Layout.alignment:     Qt.AlignHCenter
                    }

                    QGCLabel {
                        text:                 _vehicle ? _vehicle.id : ""
                        font.pointSize:       ScreenTools.largeFontPointSize
                        color:                qgcPal.text
                        Layout.alignment:     Qt.AlignHCenter
                    }

                    QGCLabel {
                        text: " | "
                        font.pointSize:       ScreenTools.largeFontPointSize
                        color:                qgcPal.text
                        Layout.alignment:     Qt.AlignHCenter
                    }

                    ColumnLayout {
                        spacing:              _margin
                        Layout.rightMargin:   compassWidget.width / 4
                        Layout.alignment:     Qt.AlignCenter

                        FlightModeMenu {
                            Layout.alignment:     Qt.AlignHCenter
                            font.pointSize:       ScreenTools.largeFontPointSize
                            color:                qgcPal.text
                            currentVehicle:       _vehicle
                        }

                        QGCLabel {
                            Layout.alignment:     Qt.AlignHCenter
                            text:                 _vehicle && _vehicle.armed ? qsTr("Armed") : qsTr("Disarmed")
                            color:                qgcPal.text
                        }
                    }
                }

                RowLayout {
                    anchors.horizontalCenter:   parent.horizontalCenter
                    spacing:                    _margin

                    Rectangle {
                        radius:          ScreenTools.defaultFontPixelHeight * 0.38
                        color:           _healthLevelBackground(_gpsHealthLevel)
                        border.width:    1
                        border.color:    _healthLevelColor(_gpsHealthLevel)
                        implicitHeight:  ScreenTools.defaultFontPixelHeight * 1.2
                        implicitWidth:   gpsHealthLabel.implicitWidth + ScreenTools.defaultFontPixelWidth * 1.2

                        QGCLabel {
                            id:                         gpsHealthLabel
                            anchors.centerIn:           parent
                            text:                       _gpsHealthText
                            color:                      _healthLevelColor(_gpsHealthLevel)
                            font.pointSize:             ScreenTools.smallFontPointSize
                            font.weight:                Font.DemiBold
                            horizontalAlignment:        Text.AlignHCenter
                        }
                    }

                    Rectangle {
                        radius:          ScreenTools.defaultFontPixelHeight * 0.38
                        color:           _healthLevelBackground(_altitudeHealthLevel)
                        border.width:    1
                        border.color:    _healthLevelColor(_altitudeHealthLevel)
                        implicitHeight:  ScreenTools.defaultFontPixelHeight * 1.2
                        implicitWidth:   altitudeHealthLabel.implicitWidth + ScreenTools.defaultFontPixelWidth * 1.2

                        QGCLabel {
                            id:                         altitudeHealthLabel
                            anchors.centerIn:           parent
                            text:                       _altitudeHealthText
                            color:                      _healthLevelColor(_altitudeHealthLevel)
                            font.pointSize:             ScreenTools.smallFontPointSize
                            font.weight:                Font.DemiBold
                            horizontalAlignment:        Text.AlignHCenter
                        }
                    }

                    Rectangle {
                        radius:          ScreenTools.defaultFontPixelHeight * 0.38
                        color:           _healthLevelBackground(_linkHealthLevel)
                        border.width:    1
                        border.color:    _healthLevelColor(_linkHealthLevel)
                        implicitHeight:  ScreenTools.defaultFontPixelHeight * 1.2
                        implicitWidth:   linkHealthLabel.implicitWidth + ScreenTools.defaultFontPixelWidth * 1.2

                        QGCLabel {
                            id:                         linkHealthLabel
                            anchors.centerIn:           parent
                            text:                       _linkHealthText
                            color:                      _healthLevelColor(_linkHealthLevel)
                            font.pointSize:             ScreenTools.smallFontPointSize
                            font.weight:                Font.DemiBold
                            horizontalAlignment:        Text.AlignHCenter
                        }
                    }
                }

                QGCFlickable {
                    anchors.horizontalCenter:   parent.horizontalCenter
                    width:          Math.min(contentWidth, vehicleList.width)
                    height:         control.height
                    contentWidth:   control.width
                    contentHeight:  control.height

                    TelemetryValuesBar {
                        id:                     control
                        settingsGroup:          factValueGrid.vehicleCardSettingsGroup
                        specificVehicleForCard: _vehicle
                    }
                }
            }
        }
    }
}
