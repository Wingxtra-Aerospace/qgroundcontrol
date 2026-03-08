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

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Palette
import QGroundControl.ScreenTools

// Important Note: Toolbar buttons must manage their checked state manually in order to support
// view switch prevention. This means they can't be checkable or autoExclusive.

Button {
    id:                 button
    height:             ScreenTools.defaultFontPixelHeight * 3
    leftPadding:        _horizontalMargin
    rightPadding:       _horizontalMargin
    checkable:          false
    hoverEnabled:       !ScreenTools.isMobile

    property bool logo: false
    property color iconColor: logo ? "transparent" : (button._active ? qgcPal.buttonHighlightText : qgcPal.buttonText)
    property real iconScale: 1.0
    property bool _active: checked || pressed

    property real _horizontalMargin: ScreenTools.defaultFontPixelWidth

    onCheckedChanged: checkable = false

    QGCPalette { id: qgcPal; colorGroupEnabled: button.enabled }

    background: Rectangle {
        anchors.fill:   parent
        radius:         ScreenTools.buttonBorderRadius
        antialiasing:   true
        color:          button._active ? qgcPal.buttonHighlight : (button.enabled && button.hovered ? qgcPal.toolStripHoverColor : Qt.rgba(0, 0, 0, 0))
        border.color:   "red"
        border.width:   QGroundControl.corePlugin.showTouchAreas ? 3 : 0

        Behavior on color {
            ColorAnimation { duration: ScreenTools.interactionAnimationDuration }
        }
    }

    contentItem: Row {
        spacing:                ScreenTools.defaultFontPixelWidth * 0.8
        anchors.verticalCenter: button.verticalCenter
        QGCColoredImage {
            id:                     _icon
            height:                 ScreenTools.defaultFontPixelHeight * 1.8 * button.iconScale
            width:                  height
            sourceSize.height:      parent.height
            fillMode:               Image.PreserveAspectFit
            color:                  button.iconColor
            source:                 button.icon.source
            anchors.verticalCenter: parent.verticalCenter
        }
        Label {
            id:                     _label
            visible:                text !== ""
            text:                   button.text
            color:                  button._active ? qgcPal.buttonHighlightText : qgcPal.buttonText
            font.family:            ScreenTools.normalFontFamily
            font.pointSize:         ScreenTools.defaultFontPointSize
            font.weight:            Font.Medium
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color {
                ColorAnimation { duration: ScreenTools.interactionAnimationDuration }
            }
        }
    }
}
