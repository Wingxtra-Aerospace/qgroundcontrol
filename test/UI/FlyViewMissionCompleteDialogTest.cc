/****************************************************************************
 *
 * (c) 2009-2026 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#include "FlyViewMissionCompleteDialogTest.h"

#include <QtCore/QFile>
#include <QtCore/QString>
#include <QtTest/QTest>

namespace {

class MissionCompleteDialogGate
{
public:
    void setActiveVehicleId(int vehicleId)
    {
        if (_missionCycleVehicleId == vehicleId) {
            return;
        }

        _missionCycleVehicleId = vehicleId;
        _resetMissionCycleState();
    }

    void setVehicleInMissionFlightMode(bool inMissionFlightMode)
    {
        _vehicleInMissionFlightMode = inMissionFlightMode;
        if (_vehicleArmed && _vehicleInMissionFlightMode) {
            _vehicleWasInMissionFlightMode = true;
        }
    }

    bool updateVehicleArmed(bool vehicleArmed, bool missionSourcesContainItems, bool hasCameraTriggerPoints)
    {
        _vehicleArmed = vehicleArmed;

        if (_vehicleArmed) {
            _vehicleWasArmed = true;
            _vehicleWasInMissionFlightMode = _vehicleInMissionFlightMode;
            _missionCompleteDialogConsumed = false;
            return false;
        }

        const bool showMissionCompleteDialog = _vehicleWasArmed
            && _vehicleWasInMissionFlightMode
            && (missionSourcesContainItems || hasCameraTriggerPoints);

        const bool shouldOpenDialog = showMissionCompleteDialog && !_missionCompleteDialogConsumed;
        if (shouldOpenDialog) {
            _missionCompleteDialogConsumed = true;
        }

        _vehicleWasArmed = false;
        _vehicleWasInMissionFlightMode = false;

        return shouldOpenDialog;
    }

    bool missionCompleteDialogConsumed() const
    {
        return _missionCompleteDialogConsumed;
    }

private:
    void _resetMissionCycleState()
    {
        _vehicleWasArmed = false;
        _vehicleWasInMissionFlightMode = false;
        _missionCompleteDialogConsumed = false;
    }

    int _missionCycleVehicleId = -1;
    bool _vehicleArmed = false;
    bool _vehicleWasArmed = false;
    bool _vehicleInMissionFlightMode = false;
    bool _vehicleWasInMissionFlightMode = false;
    bool _missionCompleteDialogConsumed = false;
};

QString loadMissionCompleteDialogSource()
{
    QFile qmlFile(QStringLiteral(":/qml/QGroundControl/FlightDisplay/FlyViewMissionCompleteDialog.qml"));
    if (!qmlFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return {};
    }

    return QString::fromUtf8(qmlFile.readAll());
}

}

void FlyViewMissionCompleteDialogTest::init()
{
    UnitTest::init();
}

void FlyViewMissionCompleteDialogTest::cleanup()
{
    UnitTest::cleanup();
}

void FlyViewMissionCompleteDialogTest::_testOneShotPerCycleAndVehicle()
{
    MissionCompleteDialogGate gate;
    const bool missionSourcesContainItems = true;
    const bool hasCameraTriggerPoints = false;

    gate.setActiveVehicleId(1);
    gate.setVehicleInMissionFlightMode(true);

    QVERIFY(!gate.updateVehicleArmed(true, missionSourcesContainItems, hasCameraTriggerPoints));
    QVERIFY(gate.updateVehicleArmed(false, missionSourcesContainItems, hasCameraTriggerPoints));
    QVERIFY(gate.missionCompleteDialogConsumed());

    // Additional disarm updates in the same cycle must not re-trigger.
    QVERIFY(!gate.updateVehicleArmed(false, missionSourcesContainItems, hasCameraTriggerPoints));

    // Active vehicle switch starts a new logical cycle.
    gate.setActiveVehicleId(2);
    QVERIFY(!gate.missionCompleteDialogConsumed());

    gate.setVehicleInMissionFlightMode(true);
    QVERIFY(!gate.updateVehicleArmed(true, missionSourcesContainItems, hasCameraTriggerPoints));
    QVERIFY(gate.updateVehicleArmed(false, missionSourcesContainItems, hasCameraTriggerPoints));
    QVERIFY(gate.missionCompleteDialogConsumed());
}

void FlyViewMissionCompleteDialogTest::_testRemovePlanUsesInjectedMissionController()
{
    const QString source = loadMissionCompleteDialogSource();
    QVERIFY(!source.isEmpty());

    QVERIFY(source.contains(QStringLiteral("function _removePlanFromVehicle()")));
    QVERIFY(source.contains(QStringLiteral("missionController.removeAllFromVehicle()")));
    QVERIFY(!source.contains(QStringLiteral("_planController.removeAllFromVehicle()")));
}

