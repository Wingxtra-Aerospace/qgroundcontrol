/****************************************************************************
 *
 * (c) 2009-2020 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Vehicle

ToolStripAction {
    text:           qsTr("Checklist")
    iconSource:     "/qmlimages/check.svg"
    visible:        _useChecklist
    enabled:        _useChecklist && _primaryVehicle && !_primaryVehicle.armed

    property bool attentionRequested: _useChecklist && _primaryVehicle && !_primaryVehicle.armed && (_primaryVehicle.checkListState !== Vehicle.CheckListPassed)
    property bool useStatusColor: _useChecklist && _primaryVehicle && !_primaryVehicle.armed
    property bool _checklistPassed: _primaryVehicle && (_primaryVehicle.checkListState === Vehicle.CheckListPassed)
    property var statusColor: attentionRequested ? QGroundControl.globalPalette.colorRed : (_checklistPassed ? QGroundControl.globalPalette.colorGreen : QGroundControl.globalPalette.buttonText)

    property var  _vehicleManager:  QGroundControl.multiVehicleManager
    property var  _activeVehicle:   _vehicleManager.activeVehicle
    readonly property var _primaryVehicle: (_activeVehicle ? _activeVehicle :
                                            ((_vehicleManager && _vehicleManager.vehicles && _vehicleManager.vehicles.count > 0) ?
                                                _vehicleManager.vehicles.get(0) : null))
    property bool _useChecklist:    QGroundControl.settingsManager.appSettings.useChecklist.rawValue &&
                                    QGroundControl.corePlugin.options.preFlightChecklistUrl.toString().length
}
