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

// Label control whichs pop up a flight mode change menu when clicked
QGCLabel {
    id:     _root
    text:   currentVehicle ? currentVehicle.flightMode : qsTr("N/A", "No data to display")

    property var    currentVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    property real   mouseAreaLeftMargin:    0
    property var    _qgcPal:                QGroundControl.globalPalette

    MouseArea {
        id:                 mouseArea
        visible:            currentVehicle && currentVehicle.flightModeSetAvailable
        anchors.leftMargin: mouseAreaLeftMargin
        anchors.fill:       parent
        onClicked: {
            if (!mainWindow || !mainWindow.contentItem) {
                flightModesPopup.open()
                return
            }

            const overlayPos = _root.mapToItem(mainWindow.contentItem, 0, _root.height + (ScreenTools.defaultFontPixelHeight * 0.3))
            const leftInset = ScreenTools.defaultFontPixelWidth * 0.6
            const rightLimit = mainWindow.contentItem.width - flightModesPopup.width - leftInset
            const bottomLimit = mainWindow.contentItem.height - flightModesPopup.height - leftInset
            const desiredX = overlayPos.x + ((_root.width - flightModesPopup.width) / 2)

            flightModesPopup.x = Math.max(leftInset, Math.min(rightLimit, desiredX))
            flightModesPopup.y = Math.max(leftInset, Math.min(bottomLimit, overlayPos.y))
            flightModesPopup.open()
        }
    }

    Popup {
        id:                     flightModesPopup
        parent:                 (mainWindow && mainWindow.contentItem) ? mainWindow.contentItem : _root
        modal:                  true
        focus:                  true
        closePolicy:            Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding:                ScreenTools.defaultFontPixelHeight * 0.55
        width:                  Math.max(ScreenTools.defaultFontPixelWidth * 13.5, modeColumn.implicitWidth + (padding * 2))
        height:                 Math.min((_maxContentHeight + (padding * 2)), (modeColumn.implicitHeight + (padding * 2)))

        readonly property real _maxContentHeight: (mainWindow && mainWindow.contentItem)
                                                    ? (mainWindow.contentItem.height * 0.46)
                                                    : (ScreenTools.defaultFontPixelHeight * 14)

        background: Rectangle {
            color:              _qgcPal.window
            opacity:            0.96
            radius:             ScreenTools.panelCornerRadius
            border.width:       1
            border.color:       _qgcPal.groupBorder
        }

        contentItem: QGCFlickable {
            clip:                   true
            contentWidth:           width
            contentHeight:          modeColumn.implicitHeight
            interactive:            contentHeight > height

            ScrollBar.vertical: ScrollBar {
                policy:             contentHeight > parent.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }

            ColumnLayout {
                id:                     modeColumn
                spacing:                ScreenTools.defaultFontPixelHeight * 0.3
                width:                  flightModesPopup.width - (flightModesPopup.padding * 2)

                Repeater {
                    model: currentVehicle ? currentVehicle.flightModes : []

                    QGCButton {
                        Layout.fillWidth:   true
                        text:               modelData
                        checkable:          true
                        checked:            currentVehicle && currentVehicle.flightMode === modelData
                        onClicked: {
                            currentVehicle.flightMode = text
                            flightModesPopup.close()
                        }
                    }
                }
            }
        }
    }
}
