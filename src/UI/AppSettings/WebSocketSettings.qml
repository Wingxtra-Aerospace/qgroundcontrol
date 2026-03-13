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
import QGroundControl.Controls
import QGroundControl.ScreenTools
import QGroundControl.Palette

ColumnLayout {
    spacing: _rowSpacing

    function _normalizePath(path) {
        if (path === undefined || path === null) {
            return ""
        }
        const text = path.toString()
        if (text.startsWith("file:///")) {
            return text.substring(8)
        }
        return text
    }

    function saveSettings() {
        const listenPortValue = parseInt(listenPortField.text)
        const udpForwardPortValue = parseInt(udpForwardPortField.text)
        subEditConfig.listenAddress = listenAddressField.text
        subEditConfig.listenPort = isNaN(listenPortValue) ? subEditConfig.listenPort : listenPortValue
        subEditConfig.secureMode = secureModeCheck.checked
        subEditConfig.certificatePath = certPathField.text
        subEditConfig.privateKeyPath = keyPathField.text
        subEditConfig.udpForwardingEnabled = udpForwardCheck.checked
        subEditConfig.udpForwardHost = udpForwardHostField.text
        subEditConfig.udpForwardPort = isNaN(udpForwardPortValue) ? subEditConfig.udpForwardPort : udpForwardPortValue
    }

    QGCLabel {
        Layout.preferredWidth: _secondColumnWidth
        Layout.fillWidth: true
        font.pointSize: ScreenTools.smallFontPointSize
        wrapMode: Text.WordWrap
        text: qsTr("Nexus Bridge local input. This build accepts localhost listen addresses only (127.0.0.1/::1). Use WSS for HTTPS browser integrations.")
    }

    GridLayout {
        columns: 2
        rowSpacing: _rowSpacing
        columnSpacing: _colSpacing

        QGCLabel { text: qsTr("Listen Address") }
        QGCTextField {
            id: listenAddressField
            Layout.preferredWidth: _secondColumnWidth
            text: subEditConfig.listenAddress
            placeholderText: qsTr("127.0.0.1")
        }

        QGCLabel { text: qsTr("Listen Port") }
        QGCTextField {
            id: listenPortField
            Layout.preferredWidth: _secondColumnWidth
            text: subEditConfig.listenPort.toString()
            inputMethodHints: Qt.ImhFormattedNumbersOnly
        }
    }

    QGCCheckBoxSlider {
        id: secureModeCheck
        Layout.fillWidth: true
        text: qsTr("Enable TLS (WSS)")
        checked: subEditConfig.secureMode
    }

    GridLayout {
        columns: 2
        rowSpacing: _rowSpacing
        columnSpacing: _colSpacing
        visible: secureModeCheck.checked

        QGCLabel { text: qsTr("Certificate File") }
        RowLayout {
            spacing: _colSpacing
            QGCTextField {
                id: certPathField
                Layout.preferredWidth: _secondColumnWidth
                text: subEditConfig.certificatePath
                placeholderText: qsTr("PEM/CRT file path")
            }
            QGCButton {
                text: qsTr("Browse")
                onClicked: certDialog.openForLoad()
                QGCFileDialog {
                    id: certDialog
                    title: qsTr("Choose certificate file")
                    selectFolder: false
                    onAcceptedForLoad: (file) => certPathField.text = _normalizePath(file)
                }
            }
        }

        QGCLabel { text: qsTr("Private Key File") }
        RowLayout {
            spacing: _colSpacing
            QGCTextField {
                id: keyPathField
                Layout.preferredWidth: _secondColumnWidth
                text: subEditConfig.privateKeyPath
                placeholderText: qsTr("PEM key path")
            }
            QGCButton {
                text: qsTr("Browse")
                onClicked: keyDialog.openForLoad()
                QGCFileDialog {
                    id: keyDialog
                    title: qsTr("Choose private key file")
                    selectFolder: false
                    onAcceptedForLoad: (file) => keyPathField.text = _normalizePath(file)
                }
            }
        }
    }

    QGCCheckBoxSlider {
        id: udpForwardCheck
        Layout.fillWidth: true
        text: qsTr("Enable UDP Forwarding Fallback")
        checked: subEditConfig.udpForwardingEnabled
    }

    GridLayout {
        columns: 2
        rowSpacing: _rowSpacing
        columnSpacing: _colSpacing
        visible: udpForwardCheck.checked

        QGCLabel { text: qsTr("UDP Target Host") }
        QGCTextField {
            id: udpForwardHostField
            Layout.preferredWidth: _secondColumnWidth
            text: subEditConfig.udpForwardHost
            placeholderText: qsTr("127.0.0.1")
        }

        QGCLabel { text: qsTr("UDP Target Port") }
        QGCTextField {
            id: udpForwardPortField
            Layout.preferredWidth: _secondColumnWidth
            text: subEditConfig.udpForwardPort.toString()
            inputMethodHints: Qt.ImhFormattedNumbersOnly
        }
    }
}
