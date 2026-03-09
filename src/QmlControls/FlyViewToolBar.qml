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
import QtQuick.Dialogs

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Palette
import QGroundControl.MultiVehicleManager
import QGroundControl.ScreenTools
import QGroundControl.Controllers

Rectangle {
    id:     _root
    width:  parent.width
    height: ScreenTools.toolbarHeight
    color:  qgcPal.toolbarBackground

    property var    _activeVehicle:     QGroundControl.multiVehicleManager.activeVehicle
    property bool   _communicationLost: _activeVehicle ? _activeVehicle.vehicleLinkManager.communicationLost : false
    property color  _mainStatusBGColor: qgcPal.brandingBlue
    property string _dateTimeText:      ""
    property int    _unreadNotifications: _activeVehicle ? _activeVehicle.messageCount : 0

    function _updateDateTimeText() {
        _dateTimeText = Qt.formatDateTime(new Date(), "ddd, dd MMM yyyy  HH:mm:ss")
    }

    function dropMainStatusIndicatorTool() {
        mainStatusIndicator.dropMainStatusIndicator();
    }

    QGCPalette { id: qgcPal }

    Behavior on color {
        ColorAnimation { duration: ScreenTools.interactionAnimationDuration }
    }

    /// Bottom single pixel divider
    Rectangle {
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.bottom: parent.bottom
        height:         1
        color:          "black"
        visible:        qgcPal.globalTheme === QGCPalette.Light
    }

    Rectangle {
        anchors.fill: viewButtonRow
        
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0;                                     color: _mainStatusBGColor }
            GradientStop { position: currentButton.x + currentButton.width; color: _mainStatusBGColor }
            GradientStop { position: 1;                                     color: _root.color }
        }
    }

    RowLayout {
        id:                     viewButtonRow
        anchors.bottomMargin:   1
        anchors.top:            parent.top
        anchors.bottom:         parent.bottom
        spacing:                ScreenTools.defaultFontPixelWidth / 2

        Item {
            id:                     currentButton
            Layout.preferredHeight: viewButtonRow.height
            Layout.preferredWidth:  logoImage.width + (ScreenTools.defaultFontPixelWidth * 2)

            QGCColoredImage {
                id:                     logoImage
                anchors.centerIn:       parent
                height:                 ScreenTools.defaultFontPixelHeight * 1.8
                width:                  height
                sourceSize.height:      height
                fillMode:               Image.PreserveAspectFit
                color:                  "transparent"
                source:                 "/res/QGCLogoFull.svg"
            }
        }

        MainStatusIndicator {
            id: mainStatusIndicator
            Layout.preferredHeight: viewButtonRow.height
        }

        QGCButton {
            id:                 disconnectButton
            text:               qsTr("Disconnect")
            onClicked:          _activeVehicle.closeVehicle()
            visible:            _activeVehicle && _communicationLost
        }
    }

    QGCFlickable {
        id:                     toolsFlickable
        anchors.leftMargin:     ScreenTools.defaultFontPixelWidth * ScreenTools.largeFontPointRatio * 1.5
        anchors.rightMargin:    ScreenTools.defaultFontPixelWidth / 2
        anchors.left:           viewButtonRow.right
        anchors.bottomMargin:   1
        anchors.top:            parent.top
        anchors.bottom:         parent.bottom
        anchors.right:          quickActionRow.left
        contentWidth:           toolIndicators.width
        flickableDirection:     Flickable.HorizontalFlick

        FlyViewToolBarIndicators { id: toolIndicators }
    }

    RowLayout {
        id:                     quickActionRow
        anchors.verticalCenter: parent.verticalCenter
        anchors.right:          dateTimeContainer.left
        anchors.rightMargin:    ScreenTools.defaultFontPixelWidth * 0.6
        spacing:                ScreenTools.defaultFontPixelWidth * 0.25

        Item {
            Layout.preferredWidth: notificationButton.width
            Layout.preferredHeight: notificationButton.height

            QGCToolBarButton {
                id:         notificationButton
                icon.source:"/InstrumentValueIcons/announcement.svg"
                iconScale:  0.72
                iconColor:  _activeVehicle && _activeVehicle.messageTypeError
                                ? qgcPal.colorRed
                                : (_activeVehicle && _activeVehicle.messageTypeWarning
                                    ? qgcPal.colorOrange
                                    : qgcPal.buttonText)
                text:       ""
                onClicked:  mainWindow.toggleNotificationCenter()
            }

            Rectangle {
                anchors.right:          parent.right
                anchors.top:            parent.top
                anchors.rightMargin:    ScreenTools.defaultFontPixelWidth * 0.2
                anchors.topMargin:      ScreenTools.defaultFontPixelHeight * 0.2
                width:                  Math.max(ScreenTools.defaultFontPixelHeight * 0.95, unreadLabel.implicitWidth + ScreenTools.defaultFontPixelWidth * 0.35)
                height:                 ScreenTools.defaultFontPixelHeight * 0.95
                radius:                 height / 2
                color:                  qgcPal.colorOrange
                border.width:           1
                border.color:           qgcPal.toolbarBackground
                visible:                _unreadNotifications > 0

                QGCLabel {
                    id:                 unreadLabel
                    anchors.centerIn:   parent
                    text:               _unreadNotifications > 99 ? "99+" : _unreadNotifications
                    font.pointSize:     ScreenTools.smallFontPointSize * 0.92
                    font.weight:        Font.DemiBold
                    color:              "white"
                }
            }
        }

        QGCToolBarButton {
            id:         commandPaletteButton
            icon.source:"/InstrumentValueIcons/menu.svg"
            iconScale:  0.72
            text:       ""
            onClicked:  mainWindow.showToolSelectDialog()
        }
    }

    //-------------------------------------------------------------------------
    //-- Branding Logo
    Image {
        id:                     brandImage
        anchors.right:          parent.right
        anchors.top:            parent.top
        anchors.bottom:         parent.bottom
        anchors.margins:        ScreenTools.defaultFontPixelHeight * 0.66
        anchors.rightMargin:    dateTimeContainer.width + quickActionRow.width + (ScreenTools.defaultFontPixelWidth * 1.9)
        visible:                _activeVehicle && !_communicationLost && _activeBrandImage.length > 0 && x > (toolsFlickable.x + toolsFlickable.contentWidth + ScreenTools.defaultFontPixelWidth)
        fillMode:               Image.PreserveAspectFit
        source:                 _activeBrandImage
        mipmap:                 true

        property bool   _outdoorPalette:        qgcPal.globalTheme === QGCPalette.Light
        property bool   _corePluginBranding:    QGroundControl.corePlugin.brandImageIndoor.length != 0
        property string _userBrandImageIndoor:  QGroundControl.settingsManager.brandImageSettings.userBrandImageIndoor.value
        property string _userBrandImageOutdoor: QGroundControl.settingsManager.brandImageSettings.userBrandImageOutdoor.value
        property bool   _userBrandingIndoor:    QGroundControl.settingsManager.brandImageSettings.visible && _userBrandImageIndoor.length != 0
        property bool   _userBrandingOutdoor:   QGroundControl.settingsManager.brandImageSettings.visible && _userBrandImageOutdoor.length != 0
        property string _brandImageIndoor:      brandImageIndoor()
        property string _brandImageOutdoor:     brandImageOutdoor()
        property string _activeBrandImage:      _outdoorPalette ? _brandImageOutdoor : _brandImageIndoor

        function brandImageIndoor() {
            if (_userBrandingIndoor) {
                return _userBrandImageIndoor
            } else {
                if (_userBrandingOutdoor) {
                    return _userBrandImageOutdoor
                } else {
                    if (_corePluginBranding) {
                        return QGroundControl.corePlugin.brandImageIndoor
                    } else {
                        return ""
                    }
                }
            }
        }

        function brandImageOutdoor() {
            if (_userBrandingOutdoor) {
                return _userBrandImageOutdoor
            } else {
                if (_userBrandingIndoor) {
                    return _userBrandImageIndoor
                } else {
                    if (_corePluginBranding) {
                        return QGroundControl.corePlugin.brandImageOutdoor
                    } else {
                        return ""
                    }
                }
            }
        }
    }

    Rectangle {
        id:                     dateTimeContainer
        anchors.right:          parent.right
        anchors.top:            parent.top
        anchors.bottom:         parent.bottom
        anchors.margins:        ScreenTools.defaultFontPixelHeight * 0.42
        radius:                 ScreenTools.panelCornerRadius * 0.62
        color:                  qgcPal.globalTheme === QGCPalette.Light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(0.02, 0.06, 0.12, 0.58)
        border.width:           1
        border.color:           qgcPal.groupBorder
        width:                  dateTimeLabel.implicitWidth + (ScreenTools.defaultFontPixelWidth * 1.8)
        visible:                _dateTimeText.length > 0
        antialiasing:           true

        Behavior on color {
            ColorAnimation { duration: ScreenTools.interactionAnimationDuration }
        }

        QGCLabel {
            id:                         dateTimeLabel
            anchors.centerIn:           parent
            text:                       _dateTimeText
            font.pointSize:             ScreenTools.defaultFontPointSize
            font.family:                ScreenTools.normalFontFamily
            color:                      qgcPal.buttonText
            verticalAlignment:          Text.AlignVCenter
            font.weight:                Font.Medium
        }
    }

    Timer {
        id:             dateTimeTimer
        interval:       1000
        running:        true
        repeat:         true
        onTriggered:    _updateDateTimeText()
    }

    Component.onCompleted: _updateDateTimeText()

    // Small parameter download progress bar
    Rectangle {
        anchors.bottom: parent.bottom
        height:         _root.height * 0.05
        width:          _activeVehicle ? _activeVehicle.loadProgress * parent.width : 0
        color:          qgcPal.colorGreen
        visible:        !largeProgressBar.visible
    }

    // Large parameter download progress bar
    Rectangle {
        id:             largeProgressBar
        anchors.bottom: parent.bottom
        anchors.left:   parent.left
        anchors.right:  parent.right
        height:         parent.height
        color:          qgcPal.window
        visible:        _showLargeProgress

        property bool _initialDownloadComplete: _activeVehicle ? _activeVehicle.initialConnectComplete : true
        property bool _userHide:                false
        property bool _showLargeProgress:       !_initialDownloadComplete && !_userHide && qgcPal.globalTheme === QGCPalette.Light

        Connections {
            target:                 QGroundControl.multiVehicleManager
            function onActiveVehicleChanged(activeVehicle) { largeProgressBar._userHide = false }
        }

        Rectangle {
            anchors.top:    parent.top
            anchors.bottom: parent.bottom
            width:          _activeVehicle ? _activeVehicle.loadProgress * parent.width : 0
            color:          qgcPal.colorGreen
        }

        QGCLabel {
            anchors.centerIn:   parent
            text:               qsTr("Downloading")
            font.pointSize:     ScreenTools.largeFontPointSize
        }

        QGCLabel {
            anchors.margins:    _margin
            anchors.right:      parent.right
            anchors.bottom:     parent.bottom
            text:               qsTr("Click anywhere to hide")

            property real _margin: ScreenTools.defaultFontPixelWidth / 2
        }

        MouseArea {
            anchors.fill:   parent
            onClicked:      largeProgressBar._userHide = true
        }
    }
}
