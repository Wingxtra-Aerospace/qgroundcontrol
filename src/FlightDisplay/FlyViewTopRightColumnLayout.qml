/****************************************************************************
 *
 * (c) 2009-2020 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlightDisplay
import QGroundControl.FlightMap
import QGroundControl.Palette
import QGroundControl.ScreenTools
import QGroundControl.Vehicle

ColumnLayout {
    width: _rightPanelWidth

    QGCPalette { id: qgcPal }

    property bool showTerrainCard: true
    property bool showCameraCard: true
    property bool showPreflightCard: true
    property var  openChecklistFn
    property var  _vehicleManager: QGroundControl.multiVehicleManager
    property var  _activeVehicle: _vehicleManager.activeVehicle
    readonly property var _primaryVehicle: (_activeVehicle ? _activeVehicle :
                                            ((_vehicleManager && _vehicleManager.vehicles && _vehicleManager.vehicles.count > 0) ?
                                                _vehicleManager.vehicles.get(0) : null))
    property bool _useChecklist: QGroundControl.settingsManager.appSettings.useChecklist.rawValue && QGroundControl.corePlugin.options.preFlightChecklistUrl.toString().length
    property bool _checklistComplete: _primaryVehicle && (_primaryVehicle.checkListState === Vehicle.CheckListPassed)
    property bool _checklistFailed: _primaryVehicle && (_primaryVehicle.checkListState === Vehicle.CheckListFailed)
    property bool _healthReportSupported: _primaryVehicle ? _primaryVehicle.healthAndArmingCheckReport.supported : false
    property bool _canArmNow: _primaryVehicle ? (_healthReportSupported ? _primaryVehicle.healthAndArmingCheckReport.canArm : (_primaryVehicle.readyToFlyAvailable ? _primaryVehicle.readyToFly : (_primaryVehicle.allSensorsHealthy && _primaryVehicle.autopilotPlugin.setupComplete))) : false

    TerrainProgress {
        Layout.alignment:       Qt.AlignTop
        Layout.preferredWidth:  _rightPanelWidth
        showProgressCard:       showTerrainCard
    }

    // We use a Loader to load the photoVideoControlComponent only when the active vehicle is not null
    // This make it easier to implement PhotoVideoControl without having to check for the mavlink camera
    // to be null all over the place
    Loader {
        id:                 photoVideoControlLoader
        Layout.alignment:   Qt.AlignTop | Qt.AlignRight
        sourceComponent:    (globals.activeVehicle && showCameraCard) ? photoVideoControlComponent : undefined
        visible:            showCameraCard
        active:             visible

        property real rightEdgeCenterInset: visible ? parent.width - x : 0

        Component {
            id: photoVideoControlComponent

            PhotoVideoControl {
            }
        }
    }

    Rectangle {
        Layout.alignment:       Qt.AlignTop
        Layout.preferredWidth:  _rightPanelWidth
        visible:                showPreflightCard && _primaryVehicle
        radius:                 ScreenTools.panelCornerRadius
        color:                  qgcPal.globalTheme === QGCPalette.Light ? Qt.rgba(0, 0, 0, 0.03) : Qt.rgba(0.035, 0.102, 0.188, 0.76)
        border.width:           1
        border.color:           qgcPal.groupBorder
        implicitHeight:         contentLayout.implicitHeight + (ScreenTools.defaultFontPixelHeight * 0.9)
        antialiasing:           true

        ColumnLayout {
            id:                     contentLayout
            anchors.fill:           parent
            anchors.margins:        ScreenTools.defaultFontPixelHeight * 0.45
            spacing:                ScreenTools.defaultFontPixelHeight * 0.35

            QGCLabel {
                text:           qsTr("Preflight Workflow")
                font.pointSize: ScreenTools.defaultFontPointSize
                font.weight:    Font.DemiBold
            }

            QGCLabel {
                Layout.fillWidth:   true
                wrapMode:           Text.WordWrap
                text: {
                    if (_checklistComplete) {
                        return qsTr("Checklist complete. Aircraft is ready.")
                    } else if (_checklistFailed) {
                        return qsTr("Checklist has unresolved items.")
                    } else if (_useChecklist) {
                        return qsTr("Checklist in progress. Complete it before arming.")
                    } else {
                        return qsTr("Checklist is disabled in settings.")
                    }
                }
                color: _checklistComplete ? qgcPal.colorGreen : (_checklistFailed ? qgcPal.colorOrange : qgcPal.text)
            }

            QGCLabel {
                text: qsTr("Arm readiness: %1").arg(_canArmNow ? qsTr("Ready") : qsTr("Not Ready"))
                color: _canArmNow ? qgcPal.colorGreen : qgcPal.colorOrange
                font.pointSize: ScreenTools.smallFontPointSize
            }

            QGCButton {
                Layout.fillWidth:   true
                text:               _checklistComplete ? qsTr("Checklist Passed") : (_useChecklist ? qsTr("Open Checklist") : qsTr("Enable Checklist in Settings"))
                enabled:            _useChecklist && _primaryVehicle && !_primaryVehicle.armed && !_checklistComplete
                onClicked: {
                    if (openChecklistFn) {
                        openChecklistFn()
                    }
                }
            }
        }
    }
}
