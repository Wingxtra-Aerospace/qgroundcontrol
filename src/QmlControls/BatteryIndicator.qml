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
import QGroundControl.MultiVehicleManager
import QGroundControl.ScreenTools
import QGroundControl.Palette
import QGroundControl.FactSystem
import QGroundControl.FactControls
import QGroundControl.AutoPilotPlugin
import MAVLink

//-------------------------------------------------------------------------
//-- Battery Indicator
Item {
    id:             control
    anchors.top:    parent.top
    anchors.bottom: parent.bottom
    width:          batteryIndicatorRow.width

    property bool       showIndicator:      true
    property bool       waitForParameters:  false   // UI won't show until parameters are ready
    property Component  expandedPageComponent

    property var    _activeVehicle:     QGroundControl.multiVehicleManager.activeVehicle
    property var    _batterySettings:   QGroundControl.settingsManager.batteryIndicatorSettings
    property Fact   _indicatorDisplay:  _batterySettings.valueDisplay
    property bool   _showPercentage:    _indicatorDisplay.rawValue === 0
    property bool   _showVoltage:       _indicatorDisplay.rawValue === 1
    property bool   _showBoth:          _indicatorDisplay.rawValue === 2

    // Properties to hold the thresholds
    property int threshold1: _batterySettings.threshold1.rawValue
    property int threshold2: _batterySettings.threshold2.rawValue   

    Row {
        id:             batteryIndicatorRow
        anchors.top:    parent.top
        anchors.bottom: parent.bottom

        Repeater {
            model: _activeVehicle ? _activeVehicle.batteries : 0

            Loader {
                anchors.top:        parent.top
                anchors.bottom:     parent.bottom
                sourceComponent:    batteryVisual

                property var battery: object
            }
        }
    }
    MouseArea {
        anchors.fill:   parent
        onClicked: {
            mainWindow.showIndicatorDrawer(batteryPopup, control)
        }
    }

    Component {
        id: batteryPopup

        ToolIndicatorPage {
            showExpand:         expandedComponent ? true : false
            waitForParameters:  control.waitForParameters
            contentComponent:   batteryContentComponent
            expandedComponent:  batteryExpandedComponent
        }
    }

    Component {
        id: batteryVisual

        Row {
            anchors.top:    parent.top
            anchors.bottom: parent.bottom

            function _isFiniteNumber(value) {
                return typeof value === "number" && isFinite(value)
            }

            function _clampPercent(value) {
                return Math.max(0, Math.min(100, value))
            }

            function getBatteryCellVoltageText() {
                if (_isFiniteNumber(Number(battery.cellVoltage.rawValue))) {
                    return battery.cellVoltage.valueString + "V"
                }
                return ""
            }

            function getBatteryVoltageText() {
                if (_isFiniteNumber(Number(battery.voltage.rawValue))) {
                    return battery.voltage.valueString + "V"
                } else if (battery.chargeState.rawValue !== MAVLink.MAV_BATTERY_CHARGE_STATE_UNDEFINED) {
                    return battery.chargeState.enumStringValue
                }
                return qsTr("n/a")
            }

            function getEffectivePercentRemaining() {
                const displayPercent = Number(battery.displayPercentRemaining.rawValue)
                if (_isFiniteNumber(displayPercent)) {
                    return _clampPercent(displayPercent)
                }

                const reportedPercent = Number(battery.percentRemaining.rawValue)
                if (_isFiniteNumber(reportedPercent)) {
                    return _clampPercent(reportedPercent)
                }

                return NaN
            }

            function getBatteryLevelClass() {
                switch (battery.chargeState.rawValue) {
                case MAVLink.MAV_BATTERY_CHARGE_STATE_LOW:
                    return "low"
                case MAVLink.MAV_BATTERY_CHARGE_STATE_CRITICAL:
                    return "critical"
                case MAVLink.MAV_BATTERY_CHARGE_STATE_EMERGENCY:
                case MAVLink.MAV_BATTERY_CHARGE_STATE_FAILED:
                case MAVLink.MAV_BATTERY_CHARGE_STATE_UNHEALTHY:
                    return "emergency"
                default:
                    break
                }

                const effectivePercent = getEffectivePercentRemaining()
                if (_isFiniteNumber(effectivePercent)) {
                    if (effectivePercent > threshold1) {
                        return "green"
                    } else if (effectivePercent > threshold2) {
                        return "yellowGreen"
                    } else {
                        return "yellow"
                    }
                }

                return "unknown"
            }

            function getBatteryColor() {
                switch (getBatteryLevelClass()) {
                case "green":
                    return qgcPal.colorGreen
                case "yellowGreen":
                    return qgcPal.colorYellowGreen
                case "yellow":
                    return qgcPal.colorYellow
                case "low":
                    return qgcPal.colorOrange
                case "critical":
                case "emergency":
                    return qgcPal.colorRed
                default:
                    return qgcPal.text
                }
            }

            function getBatterySvgSource() {
                switch (getBatteryLevelClass()) {
                case "green":
                    return "/qmlimages/BatteryGreen.svg"
                case "yellowGreen":
                    return "/qmlimages/BatteryYellowGreen.svg"
                case "yellow":
                    return "/qmlimages/BatteryYellow.svg"
                case "low":
                    return "/qmlimages/BatteryOrange.svg"
                case "critical":
                    return "/qmlimages/BatteryCritical.svg"
                case "emergency":
                    return "/qmlimages/BatteryEMERGENCY.svg"
                default:
                    return "/qmlimages/Battery.svg"
                }
            }

            function getBatteryPercentageText() {
                const effectivePercent = getEffectivePercentRemaining()
                if (_isFiniteNumber(effectivePercent)) {
                    if (effectivePercent > 98.9) {
                        return qsTr("100%")
                    } else {
                        return Math.round(effectivePercent) + "%"
                    }
                } else if (!isNaN(battery.voltage.rawValue)) {
                    return getBatteryVoltageText()
                } else if (battery.chargeState.rawValue !== MAVLink.MAV_BATTERY_CHARGE_STATE_UNDEFINED) {
                    return battery.chargeState.enumStringValue
                }
                return qsTr("n/a")
            }

            function getPrimaryIndicatorText() {
                if (_showPercentage || _showBoth) {
                    return getBatteryPercentageText()
                }
                const cellVoltageText = getBatteryCellVoltageText()
                return cellVoltageText !== "" ? cellVoltageText : getBatteryVoltageText()
            }

            function getSecondaryIndicatorText() {
                const cellVoltageText = getBatteryCellVoltageText()
                const voltageText = getBatteryVoltageText()

                if (_showVoltage) {
                    return cellVoltageText !== "" ? voltageText : ""
                }
                if (_showPercentage) {
                    return cellVoltageText
                }
                if (_showBoth) {
                    if (cellVoltageText !== "") {
                        return cellVoltageText + " | " + voltageText
                    }
                    return voltageText
                }
                return ""
            }

            QGCColoredImage {
                anchors.top:        parent.top
                anchors.bottom:     parent.bottom
                width:              height
                sourceSize.width:   width
                source:             getBatterySvgSource()
                fillMode:           Image.PreserveAspectFit
                color:              getBatteryColor()
            }

           ColumnLayout {
                id:                     batteryInfoColumn
                anchors.top:            parent.top
                anchors.bottom:         parent.bottom
                spacing:                0

                QGCLabel {
                    Layout.alignment:       Qt.AlignHCenter
                    verticalAlignment:      Text.AlignVCenter
                    color:                  qgcPal.text
                    text:                   getPrimaryIndicatorText()
                    font.pointSize:         _showBoth ? ScreenTools.defaultFontPointSize : ScreenTools.mediumFontPointSize
                    visible:                _showBoth || _showPercentage || _showVoltage
                }

                QGCLabel {
                    Layout.alignment:       Qt.AlignHCenter
                    font.pointSize:         _showBoth ? ScreenTools.defaultFontPointSize : ScreenTools.mediumFontPointSize
                    color:                  qgcPal.text
                    text:                   getSecondaryIndicatorText()
                    visible:                getSecondaryIndicatorText() !== ""
                }
            }
        }
    }

    Component {
        id: batteryContentComponent

        ColumnLayout {
            spacing: ScreenTools.defaultFontPixelHeight / 2

            Component {
                id: batteryValuesAvailableComponent

                QtObject {
                    property bool functionAvailable:         battery.function.rawValue !== MAVLink.MAV_BATTERY_FUNCTION_UNKNOWN
                    property bool showFunction:              functionAvailable && battery.function.rawValue != MAVLink.MAV_BATTERY_FUNCTION_ALL
                    property bool temperatureAvailable:      !isNaN(battery.temperature.rawValue)
                    property bool currentAvailable:          !isNaN(battery.current.rawValue)
                    property bool mahConsumedAvailable:      !isNaN(battery.mahConsumed.rawValue)
                    property bool timeRemainingAvailable:    !isNaN(battery.timeRemaining.rawValue)
                    property bool percentRemainingAvailable: !isNaN(battery.displayPercentRemaining.rawValue) || !isNaN(battery.percentRemaining.rawValue)
                    property bool cellVoltageAvailable:      !isNaN(battery.cellVoltage.rawValue)
                    property bool cellCountAvailable:        Number(battery.cellCount.rawValue) > 0
                    property bool chargeStateAvailable:      battery.chargeState.rawValue !== MAVLink.MAV_BATTERY_CHARGE_STATE_UNDEFINED
                }
            }

            Repeater {
                model: _activeVehicle ? _activeVehicle.batteries : 0

                SettingsGroupLayout {
                    heading:        qsTr("Battery %1").arg(_activeVehicle.batteries.length === 1 ? qsTr("Status") : object.id.rawValue)
                    contentSpacing: 0
                    showDividers:   false

                    property var batteryValuesAvailable: batteryValuesAvailableLoader.item

                    Loader {
                        id:                 batteryValuesAvailableLoader
                        sourceComponent:    batteryValuesAvailableComponent

                        property var battery: object
                    }

                    LabelledLabel {
                        label:  qsTr("Charge State")
                        labelText:  object.chargeState.enumStringValue
                        visible:    batteryValuesAvailable.chargeStateAvailable
                    }

                    LabelledLabel {
                        label:      qsTr("Remaining")
                        labelText:  object.timeRemainingStr.value
                        visible:    batteryValuesAvailable.timeRemainingAvailable
                    }

                    LabelledLabel {
                        label:      qsTr("Remaining")
                        labelText:  !isNaN(object.displayPercentRemaining.rawValue)
                                        ? (object.displayPercentRemaining.valueString + " " + object.displayPercentRemaining.units)
                                        : (object.percentRemaining.valueString + " " + object.percentRemaining.units)
                        visible:    batteryValuesAvailable.percentRemainingAvailable
                    }

                    LabelledLabel {
                        label:      qsTr("Cell Voltage")
                        labelText:  object.cellVoltage.valueString + " V"
                        visible:    batteryValuesAvailable.cellVoltageAvailable
                    }

                    LabelledLabel {
                        label:      qsTr("Cells")
                        labelText:  object.cellCount.rawValue.toString()
                        visible:    batteryValuesAvailable.cellCountAvailable
                    }

                    LabelledLabel {
                        label:      qsTr("Voltage")
                        labelText:  object.voltage.valueString + " V"
                    }

                    LabelledLabel {
                        label:      qsTr("Consumed")
                        labelText:  object.mahConsumed.valueString + " " + object.mahConsumed.units
                        visible:    batteryValuesAvailable.mahConsumedAvailable
                    }

                    LabelledLabel {
                        label:      qsTr("Temperature")
                        labelText:  object.temperature.valueString + " " + object.temperature.units
                        visible:    batteryValuesAvailable.temperatureAvailable
                    }

                    LabelledLabel {
                        label:      qsTr("Function")
                        labelText:  object.function.enumStringValue
                        visible:    batteryValuesAvailable.showFunction
                    }
                }
            }
        }
    }

    Component {
        id: batteryExpandedComponent

        ColumnLayout {
            spacing: ScreenTools.defaultFontPixelHeight / 2

            FactPanelController { id: controller }

            SettingsGroupLayout {
                heading:            qsTr("Battery Display")
                Layout.fillWidth:   true

                LabelledFactComboBox {
                    id:             editModeCheckBox
                    label:          qsTr("Value")
                    fact:           _fact
                    visible:        _fact,visible

                    property Fact _fact: QGroundControl.settingsManager.batteryIndicatorSettings.valueDisplay
                }

                LabelledFactTextField {
                    label:  qsTr("Cell Count Override")
                    fact:   _cellCountOverrideFact

                    property Fact _cellCountOverrideFact: QGroundControl.settingsManager.batteryIndicatorSettings.cellCountOverride
                }

                QGCLabel {
                    Layout.fillWidth:   true
                    wrapMode:           Text.WordWrap
                    color:              qgcPal.text
                    text:               qsTr("Set to 0 for Auto. Enter a manual series cell count like 12 for a 12S battery when the vehicle does not report one.")
                }

                ColumnLayout {
                    QGCLabel { text: qsTr("Coloring") }

                    RowLayout {
                        spacing: ScreenTools.defaultFontPixelWidth * 0.05  // Reduced spacing between elements

                        // Battery 100%
                        RowLayout {
                            spacing: ScreenTools.defaultFontPixelWidth * 0.05  // Tighter spacing for icon and label
                            QGCColoredImage {
                                source: "/qmlimages/BatteryGreen.svg"
                                width: ScreenTools.defaultFontPixelWidth * 6
                                height: width
                                fillMode: Image.PreserveAspectFit
                                color: qgcPal.colorGreen
                            }
                            QGCLabel { text: qsTr("100%") }
                        }

                        // Threshold 1
                        RowLayout {
                            spacing: ScreenTools.defaultFontPixelWidth * 0.05  // Tighter spacing for icon and field
                            QGCColoredImage {
                                source: "/qmlimages/BatteryYellowGreen.svg"
                                width: ScreenTools.defaultFontPixelWidth * 6
                                height: width
                                fillMode: Image.PreserveAspectFit
                                color: qgcPal.colorYellowGreen
                            }
                            FactTextField {
                                id: threshold1Field
                                fact: _batterySettings.threshold1
                                implicitWidth: ScreenTools.defaultFontPixelWidth * 6
                                height: ScreenTools.defaultFontPixelHeight * 1.5
                                enabled: fact.visible
                                onEditingFinished: {
                                    // Validate and set the new threshold value
                                    _batterySettings.setThreshold1(parseInt(text));
                                }
                            }
                        }

                        // Threshold 2
                        RowLayout {
                            spacing: ScreenTools.defaultFontPixelWidth * 0.05  // Tighter spacing for icon and field
                            QGCColoredImage {
                                source: "/qmlimages/BatteryYellow.svg"
                                width: ScreenTools.defaultFontPixelWidth * 6
                                height: width
                                fillMode: Image.PreserveAspectFit
                                color: qgcPal.colorYellow
                            }
                            FactTextField {
                                fact: _batterySettings.threshold2
                                implicitWidth: ScreenTools.defaultFontPixelWidth * 6
                                height: ScreenTools.defaultFontPixelHeight * 1.5
                                enabled: fact.visible
                                onEditingFinished: {
                                    // Validate and set the new threshold value
                                    _batterySettings.setThreshold2(parseInt(text));                                
                                }
                            }
                        }

                        // Low state
                        RowLayout {
                            spacing: ScreenTools.defaultFontPixelWidth * 0.05  // Tighter spacing for icon and label
                            QGCColoredImage {
                                source: "/qmlimages/BatteryOrange.svg"
                                width: ScreenTools.defaultFontPixelWidth * 6
                                height: width
                                fillMode: Image.PreserveAspectFit
                                color: qgcPal.colorOrange
                            }
                            QGCLabel { text: qsTr("Low") }
                        }

                        // Critical state
                        RowLayout {
                            spacing: ScreenTools.defaultFontPixelWidth * 0.05  // Tighter spacing for icon and label
                            QGCColoredImage {
                                source: "/qmlimages/BatteryCritical.svg"
                                width: ScreenTools.defaultFontPixelWidth * 6
                                height: width
                                fillMode: Image.PreserveAspectFit
                                color: qgcPal.colorRed
                            }
                            QGCLabel { text: qsTr("Critical") }
                        }
                    }
                }
            }

            Loader {
                Layout.fillWidth: true
                sourceComponent: expandedPageComponent
            }

            SettingsGroupLayout {
                visible: _activeVehicle.autopilotPlugin.knownVehicleComponentAvailable(AutoPilotPlugin.KnownPowerVehicleComponent) &&
                            QGroundControl.corePlugin.showAdvancedUI

                LabelledButton {
                    label:      qsTr("Vehicle Power")
                    buttonText: qsTr("Configure")

                    onClicked: {
                        mainWindow.showKnownVehicleComponentConfigPage(AutoPilotPlugin.KnownPowerVehicleComponent)
                        mainWindow.closeIndicatorDrawer()
                    }
                }                
            }
        }
    }
}
