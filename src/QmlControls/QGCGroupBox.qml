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

import QGroundControl.Palette
import QGroundControl.ScreenTools

GroupBox {
    id: control

    QGCPalette { id: qgcPal; colorGroupEnabled: enabled }

    background: Rectangle {
        y:      control.topPadding - control.padding
        width:  parent.width
        height: parent.height - control.topPadding + control.padding
        color:  qgcPal.windowShade
        radius: ScreenTools.panelCornerRadius * 0.72
        border.width: 1
        border.color: qgcPal.groupBorder
        antialiasing: true
    }

    label: QGCLabel {
        width:  control.availableWidth
        text:   control.title
        font.weight: Font.DemiBold
        color: qgcPal.text
    }
}
