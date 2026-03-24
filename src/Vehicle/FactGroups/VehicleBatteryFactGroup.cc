/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#include "VehicleBatteryFactGroup.h"
#include "BatteryIndicatorSettings.h"
#include "QGCMAVLink.h"
#include "ParameterManager.h"
#include "QmlObjectListModel.h"
#include "SettingsManager.h"
#include "Vehicle.h"

#include <QtCore/QList>
#include <QtCore/QString>

namespace
{

struct BatteryConfiguration
{
    int cellCount = 0;
    double fullPackVoltage = qQNaN();
    double emptyPackVoltage = qQNaN();
};

static bool _isValidPositiveDouble(double value)
{
    return !qIsNaN(value) && qIsFinite(value) && (value > 0.0);
}

static bool _tryGetParameterDouble(Vehicle *vehicle, const QString &name, double &value)
{
    ParameterManager *const parameterManager = vehicle->parameterManager();
    if (!parameterManager->parametersReady() || !parameterManager->parameterExists(ParameterManager::defaultComponentId, name)) {
        return false;
    }

    value = parameterManager->getParameter(ParameterManager::defaultComponentId, name)->rawValue().toDouble();
    return _isValidPositiveDouble(value);
}

static bool _tryGetParameterInt(Vehicle *vehicle, const QString &name, int &value)
{
    ParameterManager *const parameterManager = vehicle->parameterManager();
    if (!parameterManager->parametersReady() || !parameterManager->parameterExists(ParameterManager::defaultComponentId, name)) {
        return false;
    }

    value = parameterManager->getParameter(ParameterManager::defaultComponentId, name)->rawValue().toInt();
    return value > 0;
}

static BatteryConfiguration _resolveBatteryConfiguration(Vehicle *vehicle, uint8_t batteryId)
{
    BatteryConfiguration config;

    BatteryIndicatorSettings *const batteryIndicatorSettings = SettingsManager::instance()->batteryIndicatorSettings();
    const int cellCountOverride = batteryIndicatorSettings->cellCountOverride()->rawValue().toInt();
    if (cellCountOverride > 0) {
        config.cellCount = cellCountOverride;
    }

    const int batteryIndex = static_cast<int>(batteryId) + 1;
    const QString px4CellCountParam = QStringLiteral("BAT%1_N_CELLS").arg(batteryIndex);
    const QString px4FullCellVoltageParam = QStringLiteral("BAT%1_V_CHARGED").arg(batteryIndex);
    const QString px4EmptyCellVoltageParam = QStringLiteral("BAT%1_V_EMPTY").arg(batteryIndex);

    double px4FullCellVoltage = qQNaN();
    double px4EmptyCellVoltage = qQNaN();
    int detectedCellCount = 0;
    if (_tryGetParameterInt(vehicle, px4CellCountParam, detectedCellCount)) {
        if (config.cellCount <= 0) {
            config.cellCount = detectedCellCount;
        }
        if (_tryGetParameterDouble(vehicle, px4FullCellVoltageParam, px4FullCellVoltage)) {
            config.fullPackVoltage = px4FullCellVoltage * static_cast<double>(config.cellCount);
        }
        if (_tryGetParameterDouble(vehicle, px4EmptyCellVoltageParam, px4EmptyCellVoltage)) {
            config.emptyPackVoltage = px4EmptyCellVoltage * static_cast<double>(config.cellCount);
        }
        return config;
    }

    if ((batteryId == 0) && _tryGetParameterInt(vehicle, QStringLiteral("BAT_N_CELLS"), detectedCellCount)) {
        if (config.cellCount <= 0) {
            config.cellCount = detectedCellCount;
        }
        if (_tryGetParameterDouble(vehicle, QStringLiteral("BAT1_V_CHARGED"), px4FullCellVoltage)) {
            config.fullPackVoltage = px4FullCellVoltage * static_cast<double>(config.cellCount);
        }
        if (_tryGetParameterDouble(vehicle, QStringLiteral("BAT1_V_EMPTY"), px4EmptyCellVoltage)) {
            config.emptyPackVoltage = px4EmptyCellVoltage * static_cast<double>(config.cellCount);
        }
        return config;
    }

    int apmCellCount = 0;
    const QStringList apmCellCountParams {
        QStringLiteral("BATT_SOC%1_NCELL").arg(batteryIndex),
        QStringLiteral("OSD_CELL_COUNT"),
        QStringLiteral("MSP_OSD_NCELLS")
    };
    for (const QString &paramName : apmCellCountParams) {
        if (_tryGetParameterInt(vehicle, paramName, apmCellCount)) {
            break;
        }
    }
    if ((config.cellCount <= 0) && (apmCellCount > 0)) {
        config.cellCount = apmCellCount;
    }

    const bool isVTOLVehicle = QGCMAVLink::isVTOL(vehicle->vehicleType());
    const bool isFixedWingVehicle = vehicle->vehicleType() == MAV_TYPE_FIXED_WING;

    QStringList fullVoltageParams;
    QStringList emptyVoltageParams;
    if (isVTOLVehicle) {
        fullVoltageParams = QStringList{QStringLiteral("Q_M_BAT_VOLT_MAX"), QStringLiteral("FWD_BAT_VOLT_MAX"), QStringLiteral("MOT_BAT_VOLT_MAX")};
        emptyVoltageParams = QStringList{QStringLiteral("Q_M_BAT_VOLT_MIN"), QStringLiteral("FWD_BAT_VOLT_MIN"), QStringLiteral("MOT_BAT_VOLT_MIN")};
    } else if (isFixedWingVehicle) {
        fullVoltageParams = QStringList{QStringLiteral("FWD_BAT_VOLT_MAX"), QStringLiteral("MOT_BAT_VOLT_MAX")};
        emptyVoltageParams = QStringList{QStringLiteral("FWD_BAT_VOLT_MIN"), QStringLiteral("MOT_BAT_VOLT_MIN")};
    } else {
        fullVoltageParams = QStringList{QStringLiteral("MOT_BAT_VOLT_MAX"), QStringLiteral("Q_M_BAT_VOLT_MAX"), QStringLiteral("FWD_BAT_VOLT_MAX")};
        emptyVoltageParams = QStringList{QStringLiteral("MOT_BAT_VOLT_MIN"), QStringLiteral("Q_M_BAT_VOLT_MIN"), QStringLiteral("FWD_BAT_VOLT_MIN")};
    }

    for (const QString &paramName : fullVoltageParams) {
        if (_tryGetParameterDouble(vehicle, paramName, config.fullPackVoltage)) {
            break;
        }
    }

    for (const QString &paramName : emptyVoltageParams) {
        if (_tryGetParameterDouble(vehicle, paramName, config.emptyPackVoltage)) {
            break;
        }
    }

    const QString batteryPrefix = (batteryId == 0) ? QStringLiteral("BATT") : QStringLiteral("BATT%1").arg(batteryIndex);
    if (!_isValidPositiveDouble(config.emptyPackVoltage)) {
        const QStringList lowVoltageParams {
            QStringLiteral("%1_LOW_VOLT").arg(batteryPrefix),
            QStringLiteral("%1_CRT_VOLT").arg(batteryPrefix)
        };
        for (const QString &paramName : lowVoltageParams) {
            if (_tryGetParameterDouble(vehicle, paramName, config.emptyPackVoltage)) {
                break;
            }
        }
    }

    return config;
}

static double _calculateDisplayPercent(const BatteryConfiguration &config, double totalVoltage, double reportedPercent)
{
    if (_isValidPositiveDouble(config.fullPackVoltage) &&
        _isValidPositiveDouble(config.emptyPackVoltage) &&
        qIsFinite(totalVoltage) &&
        (config.fullPackVoltage > config.emptyPackVoltage)) {
        const double calculatedPercent = ((totalVoltage - config.emptyPackVoltage) / (config.fullPackVoltage - config.emptyPackVoltage)) * 100.0;
        return qBound(0.0, calculatedPercent, 100.0);
    }

    if (qIsFinite(reportedPercent)) {
        return qBound(0.0, reportedPercent, 100.0);
    }

    return qQNaN();
}

static void _refreshDerivedBatteryFacts(Vehicle *vehicle, VehicleBatteryFactGroup *group)
{
    const BatteryConfiguration config = _resolveBatteryConfiguration(vehicle, static_cast<uint8_t>(group->id()->rawValue().toUInt()));
    const double totalVoltage = group->voltage()->rawValue().toDouble();
    const double reportedPercent = group->percentRemaining()->rawValue().toDouble();

    int cellCount = group->cellCount()->rawValue().toInt();
    if ((cellCount <= 0) && (config.cellCount > 0)) {
        cellCount = config.cellCount;
        group->cellCount()->setRawValue(cellCount);
    }

    const bool derivedCellVoltage = (cellCount > 0) && qIsFinite(totalVoltage);
    if (derivedCellVoltage) {
        group->cellVoltage()->setRawValue(totalVoltage / static_cast<double>(cellCount));
    }

    group->displayPercentRemaining()->setRawValue(_calculateDisplayPercent(config, totalVoltage, reportedPercent));
}

} // namespace

VehicleBatteryFactGroup::VehicleBatteryFactGroup(uint8_t batteryId, QObject *parent)
    : FactGroup(1000, QStringLiteral(":/json/Vehicle/BatteryFact.json"), parent)
{
    _addFact(&_batteryIdFact);
    _addFact(&_batteryFunctionFact);
    _addFact(&_batteryTypeFact);
    _addFact(&_voltageFact);
    _addFact(&_cellVoltageFact);
    _addFact(&_cellCountFact);
    _addFact(&_currentFact);
    _addFact(&_mahConsumedFact);
    _addFact(&_temperatureFact);
    _addFact(&_percentRemainingFact);
    _addFact(&_displayPercentRemainingFact);
    _addFact(&_timeRemainingFact);
    _addFact(&_timeRemainingStrFact);
    _addFact(&_chargeStateFact);
    _addFact(&_instantPowerFact);

    _batteryIdFact.setRawValue(batteryId);
    _batteryFunctionFact.setRawValue(MAV_BATTERY_FUNCTION_UNKNOWN);
    _batteryTypeFact.setRawValue(MAV_BATTERY_TYPE_UNKNOWN);
    _voltageFact.setRawValue(qQNaN());
    _cellVoltageFact.setRawValue(qQNaN());
    _cellCountFact.setRawValue(0);
    _currentFact.setRawValue(qQNaN());
    _mahConsumedFact.setRawValue(qQNaN());
    _temperatureFact.setRawValue(qQNaN());
    _percentRemainingFact.setRawValue(qQNaN());
    _displayPercentRemainingFact.setRawValue(qQNaN());
    _timeRemainingFact.setRawValue(qQNaN());
    _chargeStateFact.setRawValue(MAV_BATTERY_CHARGE_STATE_UNDEFINED);
    _instantPowerFact.setRawValue(qQNaN());

    (void) connect(&_timeRemainingFact, &Fact::rawValueChanged, this, &VehicleBatteryFactGroup::_timeRemainingChanged);
}

void VehicleBatteryFactGroup::handleMessage(Vehicle *vehicle, const mavlink_message_t &message)
{
    switch (message.msgid) {
    case MAVLINK_MSG_ID_HIGH_LATENCY:
        _handleHighLatency(vehicle, message);
        break;
    case MAVLINK_MSG_ID_HIGH_LATENCY2:
        _handleHighLatency2(vehicle, message);
        break;
    case MAVLINK_MSG_ID_BATTERY_STATUS:
        _handleBatteryStatus(vehicle, message);
        break;
    default:
        break;
    }
}

void VehicleBatteryFactGroup::_handleHighLatency(Vehicle *vehicle, const mavlink_message_t &message)
{
    mavlink_high_latency_t highLatency{};
    mavlink_msg_high_latency_decode(&message, &highLatency);

    VehicleBatteryFactGroup *const group = _findOrAddBatteryGroupById(vehicle, 0);
    group->percentRemaining()->setRawValue((highLatency.battery_remaining == UINT8_MAX) ? qQNaN() : highLatency.battery_remaining);
    _refreshDerivedBatteryFacts(vehicle, group);

    group->_setTelemetryAvailable(true);
}

void VehicleBatteryFactGroup::_handleHighLatency2(Vehicle *vehicle, const mavlink_message_t &message)
{
    mavlink_high_latency2_t highLatency2{};
    mavlink_msg_high_latency2_decode(&message, &highLatency2);

    VehicleBatteryFactGroup *const group = _findOrAddBatteryGroupById(vehicle, 0);
    group->percentRemaining()->setRawValue((highLatency2.battery == -1) ? qQNaN() : highLatency2.battery);
    _refreshDerivedBatteryFacts(vehicle, group);

    group->_setTelemetryAvailable(true);
}

void VehicleBatteryFactGroup::_handleBatteryStatus(Vehicle *vehicle, const mavlink_message_t &message)
{
    mavlink_battery_status_t batteryStatus{};
    mavlink_msg_battery_status_decode(&message, &batteryStatus);

    VehicleBatteryFactGroup *const group = _findOrAddBatteryGroupById(vehicle, batteryStatus.id);

    QList<double> voltageSamples;
    double totalVoltage = qQNaN();
    for (int i = 0; i < 10; i++) {
        const double cellVoltage = ((batteryStatus.voltages[i] == UINT16_MAX)) ? qQNaN() : (static_cast<double>(batteryStatus.voltages[i]) / 1000.0);
        if (qIsNaN(cellVoltage)) {
            break;
        }
        voltageSamples.append(cellVoltage);
        if (i == 0) {
            totalVoltage = cellVoltage;
        } else {
            totalVoltage += cellVoltage;
        }
    }

    for (int i = 0; i < 4; i++) {
        const double cellVoltage = ((batteryStatus.voltages_ext[i] == 0)) ? qQNaN() : (static_cast<double>(batteryStatus.voltages_ext[i]) / 1000.0);
        if (qIsNaN(cellVoltage)) {
            break;
        }
        voltageSamples.append(cellVoltage);
        totalVoltage += cellVoltage;
    }

    bool telemetryContainsPerCellVoltages = !voltageSamples.isEmpty();
    for (const double sampleVoltage : voltageSamples) {
        if (sampleVoltage > 5.5) {
            telemetryContainsPerCellVoltages = false;
            break;
        }
    }

    const int cellCount = telemetryContainsPerCellVoltages ? voltageSamples.count() : 0;
    const double averageCellVoltage = (cellCount > 0 && !qIsNaN(totalVoltage)) ? (totalVoltage / static_cast<double>(cellCount)) : qQNaN();

    group->function()->setRawValue(batteryStatus.battery_function);
    group->type()->setRawValue(batteryStatus.type);
    group->temperature()->setRawValue((batteryStatus.temperature == INT16_MAX) ? qQNaN() : (static_cast<double>(batteryStatus.temperature) / 100.0));
    group->voltage()->setRawValue(totalVoltage);
    group->cellVoltage()->setRawValue(averageCellVoltage);
    group->cellCount()->setRawValue(cellCount);
    group->current()->setRawValue((batteryStatus.current_battery == -1) ? qQNaN() : (static_cast<double>(batteryStatus.current_battery) / 100.0));
    group->mahConsumed()->setRawValue((batteryStatus.current_consumed == -1) ? qQNaN() : batteryStatus.current_consumed);
    group->percentRemaining()->setRawValue((batteryStatus.battery_remaining == -1) ? qQNaN() : batteryStatus.battery_remaining);
    group->timeRemaining()->setRawValue((batteryStatus.time_remaining == 0) ? qQNaN() : batteryStatus.time_remaining);
    group->chargeState()->setRawValue(batteryStatus.charge_state);
    group->instantPower()->setRawValue(totalVoltage * group->current()->rawValue().toDouble());
    _refreshDerivedBatteryFacts(vehicle, group);

    group->_setTelemetryAvailable(true);
}

void VehicleBatteryFactGroup::handleMessageForFactGroupCreation(Vehicle *vehicle, const mavlink_message_t &message)
{
    switch (message.msgid) {
    case MAVLINK_MSG_ID_HIGH_LATENCY:
    case MAVLINK_MSG_ID_HIGH_LATENCY2:
        _findOrAddBatteryGroupById(vehicle, 0);
        break;
    case MAVLINK_MSG_ID_BATTERY_STATUS:
    {
        mavlink_battery_status_t batteryStatus{};
        mavlink_msg_battery_status_decode(&message, &batteryStatus);
        _findOrAddBatteryGroupById(vehicle, batteryStatus.id);
    }
    default:
        break;
    }
}

VehicleBatteryFactGroup *VehicleBatteryFactGroup::_findOrAddBatteryGroupById(Vehicle *vehicle, uint8_t batteryId)
{
    QmlObjectListModel *const batteries = vehicle->batteries();

    // We maintain the list in order sorted by battery id so the ui shows them sorted.
    for (int i = 0; i < batteries->count(); i++) {
        VehicleBatteryFactGroup *const group = batteries->value<VehicleBatteryFactGroup*>(i);
        const int listBatteryId = group->id()->rawValue().toInt();
        if (listBatteryId > batteryId) {
            VehicleBatteryFactGroup *const newBatteryGroup = new VehicleBatteryFactGroup(batteryId, batteries);
            batteries->insert(i, newBatteryGroup);
            vehicle->_addFactGroup(newBatteryGroup, QStringLiteral("%1%2").arg(_batteryFactGroupNamePrefix).arg(batteryId));
            (void) QObject::connect(vehicle->parameterManager(), &ParameterManager::parametersReadyChanged, newBatteryGroup,
                                    [vehicle, newBatteryGroup](bool ready) {
                                        if (ready) {
                                            _refreshDerivedBatteryFacts(vehicle, newBatteryGroup);
                                        }
                                    });
            (void) QObject::connect(SettingsManager::instance()->batteryIndicatorSettings()->cellCountOverride(), &Fact::rawValueChanged, newBatteryGroup,
                                    [vehicle, newBatteryGroup](const QVariant &) {
                                        _refreshDerivedBatteryFacts(vehicle, newBatteryGroup);
                                    });
            return newBatteryGroup;
        } else if (listBatteryId == batteryId) {
            return group;
        }
    }

    VehicleBatteryFactGroup *const newBatteryGroup = new VehicleBatteryFactGroup(batteryId, batteries);
    batteries->append(newBatteryGroup);
    vehicle->_addFactGroup(newBatteryGroup, QStringLiteral("%1%2").arg(_batteryFactGroupNamePrefix).arg(batteryId));
    (void) QObject::connect(vehicle->parameterManager(), &ParameterManager::parametersReadyChanged, newBatteryGroup,
                            [vehicle, newBatteryGroup](bool ready) {
                                if (ready) {
                                    _refreshDerivedBatteryFacts(vehicle, newBatteryGroup);
                                }
                            });
    (void) QObject::connect(SettingsManager::instance()->batteryIndicatorSettings()->cellCountOverride(), &Fact::rawValueChanged, newBatteryGroup,
                            [vehicle, newBatteryGroup](const QVariant &) {
                                _refreshDerivedBatteryFacts(vehicle, newBatteryGroup);
                            });

    return newBatteryGroup;
}

void VehicleBatteryFactGroup::_timeRemainingChanged(const QVariant &value)
{
    if (qIsNaN(value.toDouble())) {
        _timeRemainingStrFact.setRawValue("--:--:--");
    } else {
        const int totalSeconds = value.toInt();
        const int hours = totalSeconds / 3600;
        const int minutes = (totalSeconds % 3600) / 60;
        const int seconds = totalSeconds % 60;

        _timeRemainingStrFact.setRawValue(QString::asprintf("%02dH:%02dM:%02dS", hours, minutes, seconds));
    }
}
