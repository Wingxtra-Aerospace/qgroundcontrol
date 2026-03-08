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

import QGroundControl
import QGroundControl.Vehicle
import QGroundControl.Controls

/// Popup container for preflight checklists
QGCPopupDialog {
    id:         _root
    title:      qsTr("Pre-Flight Checklist")
    buttons:    Dialog.Close

    property var    _vehicleManager:    QGroundControl.multiVehicleManager
    property var    _activeVehicle:     QGroundControl.multiVehicleManager.activeVehicle
    property int    _vehicleCount:      (_vehicleManager && _vehicleManager.vehicles) ? _vehicleManager.vehicles.count : 0
    property bool   _useChecklist:      QGroundControl.settingsManager.appSettings.useChecklist.rawValue && QGroundControl.corePlugin.options.preFlightChecklistUrl.toString().length
    property bool   _enforceChecklist:  _useChecklist && QGroundControl.settingsManager.appSettings.enforceChecklist.rawValue
    property bool   _checklistComplete: _isChecklistComplete(_activeVehicle)

    on_ActiveVehicleChanged: _showPreFlightChecklistIfNeeded()
    on_VehicleCountChanged: _showPreFlightChecklistIfNeeded()

    Connections {
        target:                             mainWindow
        onShowPreFlightChecklistIfNeeded:   _root._showPreFlightChecklistIfNeeded()
    }

    function _resolveChecklistVehicle() {
        if (_activeVehicle) {
            return _activeVehicle
        }

        if (!_vehicleManager || !_vehicleManager.vehicles || _vehicleManager.vehicles.count === 0) {
            return null
        }

        return _vehicleManager.vehicles.get(0)
    }

    function _isChecklistComplete(vehicle) {
        return !!vehicle && vehicle.checkListState === Vehicle.CheckListPassed
    }

    function _showPreFlightChecklistIfNeeded() {
        if (!_enforceChecklist) {
            return
        }

        const checklistVehicle = _resolveChecklistVehicle()
        if (!checklistVehicle) {
            return
        }

        if (!_activeVehicle && checklistVehicle && _vehicleManager) {
            _vehicleManager.activeVehicle = checklistVehicle
        }

        if (!_isChecklistComplete(checklistVehicle)) {
            popupTimer.restart()
        }
    }

    Timer {
        id:             popupTimer
        interval:       1000
        repeat:         false
        onTriggered: {
            const checklistVehicle = _resolveChecklistVehicle()
            if (!_isChecklistComplete(checklistVehicle)) {
                _root.open()
            } else {
                _root.close()
            }
        }
    }

    Loader {
        id:     checkList
        source: QGroundControl.corePlugin.options.preFlightChecklistUrl
    }

    property alias checkListItem: checkList.item

    Connections {
        target: checkList.item
        onAllChecksPassedChanged: {
            if (target.allChecksPassed) {
                popupTimer.restart()
            }
        }
    }
}
