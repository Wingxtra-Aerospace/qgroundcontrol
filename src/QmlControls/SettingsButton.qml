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
import QGroundControl.Palette
import QGroundControl.ScreenTools

Button {
    id:             control
    padding:        ScreenTools.defaultFontPixelWidth * 0.85
    hoverEnabled:   !ScreenTools.isMobile
    autoExclusive:  true
    icon.color:     textColor

    property color textColor: checked || pressed ? qgcPal.buttonHighlightText : (hovered ? qgcPal.text : qgcPal.buttonText)

    QGCPalette {
        id:                 qgcPal
        colorGroupEnabled:  control.enabled
    }

    background: Rectangle {
        color:      checked || pressed ? qgcPal.buttonHighlight : (enabled && hovered ? qgcPal.toolStripHoverColor : Qt.rgba(0,0,0,0))
        opacity:    1
        radius:     ScreenTools.panelCornerRadius * 0.75
        border.width: checked || pressed || hovered ? 1 : 0
        border.color: qgcPal.buttonBorder

        Behavior on color {
            ColorAnimation { duration: ScreenTools.interactionAnimationDuration }
        }

        Behavior on border.color {
            ColorAnimation { duration: ScreenTools.interactionAnimationDuration }
        }
    }

    contentItem: RowLayout {
        spacing: ScreenTools.defaultFontPixelWidth

        QGCColoredImage {
            source: control.icon.source
            color:  control.icon.color
            width:  ScreenTools.defaultFontPixelHeight * 1.05
            height: ScreenTools.defaultFontPixelHeight * 1.05
        }

        QGCLabel {
            id:                     displayText
            Layout.fillWidth:       true
            text:                   control.text
            color:                  control.textColor
            horizontalAlignment:    QGCLabel.AlignLeft
            font.weight:            Font.Medium

            Behavior on color {
                ColorAnimation { duration: ScreenTools.interactionAnimationDuration }
            }
        }
    }
}
