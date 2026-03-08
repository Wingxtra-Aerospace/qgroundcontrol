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

import QGroundControl.ScreenTools
import QGroundControl.Palette

Button {
    id:             control
    width:          contentLayoutItem.contentWidth + (contentMargins * 2)
    height:         width
    hoverEnabled:   !ScreenTools.isMobile
    enabled:        toolStripAction.enabled
    visible:        toolStripAction.visible
    imageSource:    toolStripAction.showAlternateIcon ? modelData.alternateIconSource : modelData.iconSource
    text:           toolStripAction.text
    checked:        toolStripAction.checked
    checkable:      toolStripAction.dropPanelComponent || modelData.checkable

    property var    toolStripAction:    undefined
    property var    dropPanel:          undefined
    property alias  radius:             buttonBkRect.radius
    property alias  fontPointSize:      innerText.font.pointSize
    property alias  imageSource:        innerImage.source
    property alias  contentWidth:       innerText.contentWidth
    property bool   _attentionEnabled:  !!toolStripAction && !!toolStripAction.attentionRequested && control.visible && control.enabled && !control.checked

    property bool forceImageScale11: false
    property real imageScale:        forceImageScale11 && (text == "") ? 0.72 : 0.58
    property real contentMargins:    innerText.height * 0.14
    property bool _hasStatusColor:   !!toolStripAction && !!toolStripAction.useStatusColor
    property color _statusColor:     _hasStatusColor ? toolStripAction.statusColor : "transparent"

    property color _currentContentColor:  _hasStatusColor ?
                                              _statusColor :
                                              ((checked || pressed) ? qgcPal.buttonHighlightText : (control.enabled && control.hovered ? qgcPal.text : qgcPal.buttonText))
    property color _currentContentColorSecondary:  (checked || pressed) ? qgcPal.buttonText : (control.enabled && control.hovered ? qgcPal.buttonHighlightText : qgcPal.buttonHighlight)

    signal dropped(int index)

    onCheckedChanged: toolStripAction.checked = checked

    on_AttentionEnabledChanged: {
        if (!_attentionEnabled) {
            shakeAnimation.stop()
            shakeTranslate.x = 0
        } else if (!shakeAnimation.running) {
            shakeAnimation.start()
        }
    }

    onClicked: {
        if (mainWindow.allowViewSwitch()) {
            dropPanel.hide()
            if (!toolStripAction.dropPanelComponent) {
                toolStripAction.triggered(this)
            } else if (checked) {
                var panelEdgeTopPoint = mapToItem(_root, width, 0)
                dropPanel.show(panelEdgeTopPoint, toolStripAction.dropPanelComponent, this)
                checked = true
                control.dropped(index)
            }
        } else if (checkable) {
            checked = !checked
        }
    }

    QGCPalette { id: qgcPal; colorGroupEnabled: control.enabled }

    transform: Translate {
        id: shakeTranslate
        x: 0
    }

    transformOrigin: Item.Center
    scale: control.pressed ? 0.97 : 1.0

    Behavior on scale {
        NumberAnimation { duration: ScreenTools.interactionAnimationDuration }
    }

    Timer {
        id:                 attentionTimer
        interval:           10000
        repeat:             true
        running:            _attentionEnabled
        triggeredOnStart:   false
        onTriggered: {
            if (_attentionEnabled && !shakeAnimation.running) {
                shakeAnimation.start()
            }
        }
    }

    SequentialAnimation {
        id:         shakeAnimation
        running:    false
        loops:      1

        NumberAnimation { target: shakeTranslate; property: "x"; to: -4; duration: 45; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeTranslate; property: "x"; to:  4; duration: 90; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeTranslate; property: "x"; to: -3; duration: 75; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeTranslate; property: "x"; to:  3; duration: 75; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeTranslate; property: "x"; to:  0; duration: 55; easing.type: Easing.InOutQuad }
    }

    contentItem: Item {
        id:                 contentLayoutItem
        anchors.fill:       parent
        anchors.margins:    contentMargins

        Column {
            anchors.centerIn:   parent
            spacing:        contentMargins * 2

            Image {
                id:                         innerImageColorful
                height:                     contentLayoutItem.height * imageScale
                width:                      contentLayoutItem.width  * imageScale
                smooth:                     true
                mipmap:                     true
                fillMode:                   Image.PreserveAspectFit
                antialiasing:               true
                sourceSize.height:          height
                sourceSize.width:           width
                anchors.horizontalCenter:   parent.horizontalCenter
                source:                     control.imageSource
                visible:                    source != "" && modelData.fullColorIcon
            }

            QGCColoredImage {
                id:                         innerImage
                height:                     contentLayoutItem.height * imageScale
                width:                      contentLayoutItem.width  * imageScale
                smooth:                     true
                mipmap:                     true
                color:                      _currentContentColor
                fillMode:                   Image.PreserveAspectFit
                antialiasing:               true
                sourceSize.height:          height
                sourceSize.width:           width
                anchors.horizontalCenter:   parent.horizontalCenter
                visible:                    source != "" && !modelData.fullColorIcon

                Behavior on color {
                    ColorAnimation { duration: ScreenTools.interactionAnimationDuration }
                }
                
                QGCColoredImage {
                    id:                         innerImageSecondColor
                    source:                     modelData.alternateIconSource
                    height:                     contentLayoutItem.height * imageScale
                    width:                      contentLayoutItem.width  * imageScale
                    smooth:                     true
                    mipmap:                     true
                    color:                      _currentContentColorSecondary
                    fillMode:                   Image.PreserveAspectFit
                    antialiasing:               true
                    sourceSize.height:          height
                    sourceSize.width:           width
                    anchors.horizontalCenter:   parent.horizontalCenter
                    visible:                    source != "" && modelData.biColorIcon

                    Behavior on color {
                        ColorAnimation { duration: ScreenTools.interactionAnimationDuration }
                    }
                }
            }

            QGCLabel {
                id:                         innerText
                text:                       control.text
                color:                      _currentContentColor
                anchors.horizontalCenter:   parent.horizontalCenter
                font.bold:                  !innerImage.visible && !innerImageColorful.visible
                font.weight:                Font.Medium
                opacity:                    !innerImage.visible ? 0.8 : 1.0

                Behavior on color {
                    ColorAnimation { duration: ScreenTools.interactionAnimationDuration }
                }
            }
        }
    }

    background: Rectangle {
        id:             buttonBkRect
        color:          (control.checked || control.pressed) ?
                            (toolStripAction.useCheckedBackgroundColor ? toolStripAction.checkedBackgroundColor : qgcPal.buttonHighlight) :
                            ((control.enabled && control.hovered) ? qgcPal.toolStripHoverColor : qgcPal.toolbarBackground)
        anchors.fill:   parent
        antialiasing:   true

        Behavior on color {
            ColorAnimation { duration: ScreenTools.interactionAnimationDuration }
        }
    }
}
