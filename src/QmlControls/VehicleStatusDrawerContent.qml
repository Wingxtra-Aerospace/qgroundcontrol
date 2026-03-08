/****************************************************************************
 *
 * (c) 2009-2026 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FactSystem
import QGroundControl.MultiVehicleManager
import QGroundControl.ScreenTools

Item {
    id: root

    property var drawer: null
    property var _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property bool _armed: _activeVehicle ? _activeVehicle.armed : false
    property bool _healthAndArmingChecksSupported: _activeVehicle ? _activeVehicle.healthAndArmingCheckReport.supported : false
    property real _spacing: ScreenTools.defaultFontPixelWidth / 2

    function _closeDrawer() {
        if (drawer && typeof drawer.close === "function") {
            drawer.close()
        } else {
            mainWindow.closeIndicatorDrawer()
        }
    }

    implicitWidth: contentFlickable.implicitWidth
    implicitHeight: contentFlickable.implicitHeight

    FactPanelController {
        id: controller
    }

    QGCFlickable {
        id: contentFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentLayout.implicitHeight
        clip: true

        ColumnLayout {
            id: contentLayout
            width: contentFlickable.width
            spacing: root._spacing

            QGCButton {
                // force arm is unavailable when canArm is false and health report is supported.
                enabled: root._armed || !root._healthAndArmingChecksSupported || root._activeVehicle.healthAndArmingCheckReport.canArm
                text: root._armed ? qsTr("Disarm") : (forceArm ? qsTr("Force Arm") : qsTr("Arm"))
                visible: root._activeVehicle
                Layout.alignment: Qt.AlignLeft

                property bool forceArm: false

                onPressAndHold: forceArm = true

                onClicked: {
                    if (root._armed) {
                        mainWindow.disarmVehicleRequest()
                    } else if (forceArm) {
                        mainWindow.forceArmVehicleRequest()
                    } else {
                        mainWindow.armVehicleRequest()
                    }
                    forceArm = false
                    root._closeDrawer()
                }
            }

            SettingsGroupLayout {
                heading: qsTr("Vehicle Messages")
                visible: root._activeVehicle && !vehicleMessageList.noMessages

                VehicleMessageList {
                    id:                 vehicleMessageList
                    activeVehicle:      root._activeVehicle
                    drawer:             root.drawer
                    Layout.fillWidth:   true
                }
            }

            SettingsGroupLayout {
                heading: qsTr("Sensor Status")
                visible: root._activeVehicle && !root._healthAndArmingChecksSupported

                GridLayout {
                    rowSpacing: root._spacing
                    columnSpacing: root._spacing
                    rows: root._activeVehicle ? root._activeVehicle.sysStatusSensorInfo.sensorNames.length : 0
                    flow: GridLayout.TopToBottom

                    Repeater {
                        model: root._activeVehicle ? root._activeVehicle.sysStatusSensorInfo.sensorNames : []
                        QGCLabel { text: modelData }
                    }

                    Repeater {
                        model: root._activeVehicle ? root._activeVehicle.sysStatusSensorInfo.sensorStatus : []
                        QGCLabel { text: modelData }
                    }
                }
            }

            SettingsGroupLayout {
                heading: qsTr("Overall Status")
                visible: root._activeVehicle && root._healthAndArmingChecksSupported && (root._activeVehicle.healthAndArmingCheckReport.problemsForCurrentMode.count > 0)

                Repeater {
                    model: root._activeVehicle ? root._activeVehicle.healthAndArmingCheckReport.problemsForCurrentMode : null
                    delegate: overallStatusDelegate
                }
            }

            ToolIndicatorPage {
                Layout.fillWidth: true
                visible: root._activeVehicle && !!root._activeVehicle.mainStatusIndicatorContentItem
                showExpand: false
                waitForParameters: true
                contentComponent: Component {
                    Loader {
                        source: root._activeVehicle ? root._activeVehicle.mainStatusIndicatorContentItem : ""
                    }
                }
            }

            SettingsGroupLayout {
                Layout.fillWidth: true
                visible: root._activeVehicle && QGroundControl.corePlugin.showAdvancedUI

                GridLayout {
                    columns: 2
                    rowSpacing: ScreenTools.defaultFontPixelHeight / 2
                    columnSpacing: ScreenTools.defaultFontPixelWidth * 2
                    Layout.fillWidth: true

                    QGCLabel { Layout.fillWidth: true; text: qsTr("Vehicle Parameters") }
                    QGCButton {
                        text: qsTr("Configure")
                        onClicked: {
                            mainWindow.showVehicleConfigParametersPage()
                            root._closeDrawer()
                        }
                    }

                    QGCLabel { Layout.fillWidth: true; text: qsTr("Vehicle Configuration") }
                    QGCButton {
                        text: qsTr("Configure")
                        onClicked: {
                            mainWindow.showVehicleConfig()
                            root._closeDrawer()
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 0.2
            }
        }
    }

    Component {
        id: overallStatusDelegate

        Column {
            Row {
                spacing: ScreenTools.defaultFontPixelHeight

                QGCLabel {
                    id: message
                    text: object.message
                    textFormat: TextEdit.RichText
                    color: object.severity == "error" ? qgcPal.colorRed : object.severity == "warning" ? qgcPal.colorOrange : qgcPal.text

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (object.description != "") {
                                object.expanded = !object.expanded
                            }
                        }
                    }
                }

                QGCColoredImage {
                    id:                     arrowDownIndicator
                    anchors.verticalCenter: parent.verticalCenter
                    height:                 1.5 * ScreenTools.defaultFontPixelWidth
                    width:                  height
                    source:                 "/qmlimages/arrow-down.png"
                    color:                  qgcPal.text
                    visible:                object.description != ""

                    MouseArea {
                        anchors.fill: parent
                        onClicked: object.expanded = !object.expanded
                    }
                }
            }

            QGCLabel {
                id:                 description
                text:               object.description
                textFormat:         TextEdit.RichText
                clip:               true
                visible:            object.expanded
                property var fact:  null

                onLinkActivated: (link) => {
                    if (link.startsWith("param://")) {
                        const paramName = link.substr(8)
                        fact = controller.getParameterFact(-1, paramName, true)
                        if (fact != null) {
                            paramEditorDialogComponent.createObject(mainWindow).open()
                        }
                    } else {
                        Qt.openUrlExternally(link)
                    }
                }

                Component {
                    id: paramEditorDialogComponent

                    ParameterEditorDialog {
                        title: qsTr("Edit Parameter")
                        fact: description.fact
                        destroyOnClose: true
                    }
                }
            }
        }
    }
}
