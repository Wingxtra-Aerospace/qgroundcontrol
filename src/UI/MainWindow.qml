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
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window
import QtCore

import QGroundControl
import QGroundControl.Palette
import QGroundControl.Controls
import QGroundControl.FactControls
import QGroundControl.ScreenTools
import QGroundControl.FlightDisplay
import QGroundControl.FlightMap

import QGroundControl.UTMSP

/// @brief Native QML top level window
/// All properties defined here are visible to all QML pages.
ApplicationWindow {
    id:             mainWindow
    visible:        true

    property bool   _utmspSendActTrigger
    property bool   _utmspStartTelemetry

    Component.onCompleted: {
        // Start the sequence of first run prompt(s)
        firstRunPromptManager.nextPrompt()
    }

    /// Saves main window position and size and re-opens it in the same position and size next time
    MainWindowSavedState {
        window: mainWindow
    }

    QtObject {
        id: firstRunPromptManager

        property var currentDialog:     null
        property var rgPromptIds:       QGroundControl.corePlugin.firstRunPromptsToShow()
        property int nextPromptIdIndex: 0

        function clearNextPromptSignal() {
            if (currentDialog) {
                currentDialog.closed.disconnect(nextPrompt)
            }
        }

        function nextPrompt() {
            if (nextPromptIdIndex < rgPromptIds.length) {
                var component = Qt.createComponent(QGroundControl.corePlugin.firstRunPromptResource(rgPromptIds[nextPromptIdIndex]));
                currentDialog = component.createObject(mainWindow)
                currentDialog.closed.connect(nextPrompt)
                currentDialog.open()
                nextPromptIdIndex++
            } else {
                currentDialog = null
                showPreFlightChecklistIfNeeded()
            }
        }
    }

    readonly property real      _topBottomMargins:          ScreenTools.defaultFontPixelHeight * 0.5
    property bool               _showFlyView:               true
    property bool               _accessibilityModeEnabled:  _uiPreferences.accessibilityModeEnabled
    property bool               _reducedMotionEnabled:      _uiPreferences.reducedMotionEnabled
    property var                _activeVehicle:             QGroundControl.multiVehicleManager.activeVehicle
    property int                _timelineUnreadCount:       0
    property int                _notificationMaxItems:      80
    property int                _notificationSequence:      0
    property string             _notificationSortMode:      "all"
    readonly property real      _rightSideDrawerOffset:     Math.max(notificationDrawer.position * notificationDrawer.width, toolSelectDrawer.position * toolSelectDrawer.width)

    font.pointSize: ScreenTools.defaultFontPointSize * (_accessibilityModeEnabled ? 1.1 : 1.0)

    Settings {
        id:         _uiPreferences
        category:   "NexusUserExperience"

        property bool accessibilityModeEnabled: false
        property bool reducedMotionEnabled:     false
    }

    ListModel {
        id: _notificationModel
    }

    function _asPlainText(text) {
        if (!text) {
            return ""
        }
        return text.toString().replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim()
    }

    function _notificationSeverityPriority(severity) {
        if (severity === "error") {
            return 0
        } else if (severity === "warning") {
            return 1
        }
        return 2
    }

    function _notificationComparator(left, right) {
        if (_notificationSortMode === "all") {
            // Show everything in plain timeline order (oldest first), no prioritization.
            return left.sequence - right.sequence
        } else if (_notificationSortMode === "newest") {
            // Show everything in reverse timeline order (newest first), no prioritization.
            return right.sequence - left.sequence
        } else if (_notificationSortMode === "recommended") {
            if (left.read !== right.read) {
                return left.read ? 1 : -1
            }
            const severityDelta = _notificationSeverityPriority(left.severity) - _notificationSeverityPriority(right.severity)
            if (severityDelta !== 0) {
                return severityDelta
            }
            return right.sequence - left.sequence
        } else if (_notificationSortMode === "severity") {
            const severityDelta = _notificationSeverityPriority(left.severity) - _notificationSeverityPriority(right.severity)
            if (severityDelta !== 0) {
                return severityDelta
            }
            return right.sequence - left.sequence
        }

        // Fallback: newest first
        return right.sequence - left.sequence
    }

    function _resortNotifications() {
        if (_notificationModel.count < 2) {
            return
        }

        const entries = []
        for (let i = 0; i < _notificationModel.count; i++) {
            entries.push(_notificationModel.get(i))
        }
        entries.sort(_notificationComparator)

        _notificationModel.clear()
        for (let i = 0; i < entries.length; i++) {
            _notificationModel.append(entries[i])
        }
    }

    function _markAllTimelineNotificationsRead() {
        let anyChanged = false
        for (let i = 0; i < _notificationModel.count; i++) {
            if (!_notificationModel.get(i).read) {
                _notificationModel.setProperty(i, "read", true)
                anyChanged = true
            }
        }
        _timelineUnreadCount = 0

        if (anyChanged && _notificationSortMode === "recommended") {
            _resortNotifications()
        }
    }

    function addNotification(title, detail, severity = "info") {
        const cleanTitle = _asPlainText(title)
        const cleanDetail = _asPlainText(detail)
        const entryRead = notificationDrawer.visible

        _notificationModel.append({
            sequence: _notificationSequence++,
            timestamp: Qt.formatDateTime(new Date(), "HH:mm:ss"),
            title: cleanTitle,
            detail: cleanDetail,
            severity: severity,
            read: entryRead
        })

        _resortNotifications()

        while (_notificationModel.count > _notificationMaxItems) {
            _notificationModel.remove(_notificationModel.count - 1)
        }

        if (!entryRead) {
            _timelineUnreadCount += 1
        }
    }

    function _vehicleSeverityToNotificationSeverity(severity) {
        if (severity <= 3) {
            return "error"
        } else if (severity <= 4) {
            return "warning"
        }
        return "info"
    }

    function _setAccessibilityMode(enabled) {
        if (_accessibilityModeEnabled === enabled) {
            return
        }
        _accessibilityModeEnabled = enabled
        _uiPreferences.accessibilityModeEnabled = enabled
    }

    function _setReducedMotionMode(enabled) {
        if (_reducedMotionEnabled === enabled) {
            return
        }
        _reducedMotionEnabled = enabled
        _uiPreferences.reducedMotionEnabled = enabled
    }

    function _dismissFlyViewControlsPopup() {
        if (flyView && (typeof flyView.dismissViewControlsPopup === "function")) {
            flyView.dismissViewControlsPopup()
        }
    }

    function toggleNotificationCenter() {
        if (notificationDrawer.visible) {
            notificationDrawer.close()
        } else {
            _dismissFlyViewControlsPopup()
            if (toolSelectDrawer.visible) {
                toolSelectDrawer.close()
            }
            if (indicatorDrawer.visible) {
                closeIndicatorDrawer()
            }
            notificationDrawer.open()
        }
    }

    //-------------------------------------------------------------------------
    //-- Global Scope Variables

    QtObject {
        id: globals

        readonly property var       activeVehicle:                  QGroundControl.multiVehicleManager.activeVehicle
        readonly property real      defaultTextHeight:              ScreenTools.defaultFontPixelHeight
        readonly property real      defaultTextWidth:               ScreenTools.defaultFontPixelWidth
        readonly property var       planMasterControllerFlyView:    flyView.planController
        readonly property var       guidedControllerFlyView:        flyView.guidedController

        // Number of QGCTextField's with validation errors. Used to prevent closing panels with validation errors.
        property int                validationErrorCount:           0 

        // Property to manage RemoteID quick access to settings page
        property bool               commingFromRIDIndicator:        false
    }

    /// Default color palette used throughout the UI
    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    //-------------------------------------------------------------------------
    //-- Actions

    signal armVehicleRequest
    signal forceArmVehicleRequest
    signal disarmVehicleRequest
    signal vtolTransitionToFwdFlightRequest
    signal vtolTransitionToMRFlightRequest
    signal showPreFlightChecklistIfNeeded

    Connections {
        target: QGroundControl.multiVehicleManager

        function onActiveVehicleChanged(activeVehicle) {
            _notificationModel.clear()
            _timelineUnreadCount = 0
            if (activeVehicle) {
                addNotification(qsTr("Vehicle Connected"), qsTr("Vehicle %1 is now active").arg(activeVehicle.id), "info")
            } else {
                addNotification(qsTr("Vehicle Disconnected"), qsTr("No active vehicle"), "warning")
            }
        }
    }

    Connections {
        target:                 globals.activeVehicle
        ignoreUnknownSignals:   true

        function onTextMessageReceived(sysid, componentid, severity, text, description) {
            const vehicleTitle = qsTr("Vehicle %1").arg(sysid)
            const detailText = description && description.length > 0 ? (text + " " + description) : text
            addNotification(vehicleTitle, detailText, _vehicleSeverityToNotificationSeverity(severity))
        }

        function onArmedChanged() {
            addNotification(qsTr("Vehicle State"), globals.activeVehicle.armed ? qsTr("Vehicle armed") : qsTr("Vehicle disarmed"), "info")
        }

        function onFlightModeChanged(flightMode) {
            addNotification(qsTr("Flight Mode"), flightMode, "info")
        }
    }

    //-------------------------------------------------------------------------
    //-- Global Scope Functions

    // This function is used to prevent view switching if there are validation errors
    function allowViewSwitch(previousValidationErrorCount = 0) {
        // Run validation on active focus control to ensure it is valid before switching views
        if (mainWindow.activeFocusControl instanceof FactTextField) {
            mainWindow.activeFocusControl._onEditingFinished()
        }
        return globals.validationErrorCount <= previousValidationErrorCount
    }

    function showPlanView() {
        if (_showFlyView) {
            _dismissFlyViewControlsPopup()
            _showFlyView = false
        }
    }

    function showFlyView() {
        if (!_showFlyView) {
            _showFlyView = true
        }
    }

    function showTool(toolTitle, toolSource, toolIcon) {
        _dismissFlyViewControlsPopup()
        toolDrawer.backIcon     = flyView.visible ? "/qmlimages/PaperPlane.svg" : "/qmlimages/Plan.svg"
        toolDrawer.toolTitle    = toolTitle
        toolDrawer.toolSource   = toolSource
        toolDrawer.toolIcon     = toolIcon
        toolDrawer.visible      = true
    }

    function showAnalyzeTool() {
        showTool(qsTr("Analyze Tools"), "qrc:/qml/QGroundControl/AnalyzeView/AnalyzeView.qml", "/qmlimages/Analyze.svg")
    }

    function showVehicleConfig() {
        showTool(qsTr("Vehicle Configuration"), "qrc:/qml/QGroundControl/VehicleSetup/SetupView.qml", "/qmlimages/Gears.svg")
    }

    function showVehicleConfigParametersPage() {
        showVehicleConfig()
        toolDrawerLoader.item.showParametersPanel()
    }

    function showKnownVehicleComponentConfigPage(knownVehicleComponent) {
        showVehicleConfig()
        let vehicleComponent = globals.activeVehicle.autopilotPlugin.findKnownVehicleComponent(knownVehicleComponent)
        if (vehicleComponent) {
            toolDrawerLoader.item.showVehicleComponentPanel(vehicleComponent)
        }
    }

    function showSettingsTool(settingsPage = "") {
        showTool(qsTr("Application Settings"), "qrc:/qml/QGroundControl/Controls/AppSettings.qml", "/res/QGCLogoWhite")
        if (settingsPage !== "") {
            toolDrawerLoader.item.showSettingsPage(settingsPage)
        }
    }

    //-------------------------------------------------------------------------
    //-- Global simple message dialog

    function showMessageDialog(dialogTitle, dialogText, buttons = Dialog.Ok, acceptFunction = null, closeFunction = null) {
        simpleMessageDialogComponent.createObject(mainWindow, { title: dialogTitle, text: dialogText, buttons: buttons, acceptFunction: acceptFunction, closeFunction: closeFunction }).open()
    }

    // This variant is only meant to be called by QGCApplication
    function _showMessageDialog(dialogTitle, dialogText) {
        showMessageDialog(dialogTitle, dialogText)
    }

    function _transientNoticeNormalizedSeverity(severity) {
        const severityText = severity ? severity.toString().toLowerCase() : "info"
        if (severityText === "success" || severityText === "warning" || severityText === "error") {
            return severityText
        }
        return "info"
    }

    function _transientNoticeAccentColor(severity) {
        switch (_transientNoticeNormalizedSeverity(severity)) {
        case "success":
            return qgcPal.colorGreen
        case "warning":
            return qgcPal.colorOrange
        case "error":
            return qgcPal.colorRed
        default:
            return qgcPal.brandingBlue
        }
    }

    function _transientNoticeGlyph(severity) {
        switch (_transientNoticeNormalizedSeverity(severity)) {
        case "success":
            return "\u2713"
        case "warning":
        case "error":
            return "!"
        default:
            return "i"
        }
    }

    function _showTransientTopMessage(dialogTitle, dialogText, durationMs, severity) {
        transientTopNoticePopup.noticeTitle = dialogTitle
        transientTopNoticePopup.noticeText = dialogText
        transientTopNoticePopup.noticeDurationMs = Math.max(2200, Number(durationMs) || 0)
        transientTopNoticePopup.noticeSeverity = _transientNoticeNormalizedSeverity(severity)
        transientTopNoticePopup.present()
    }

    Component {
        id: simpleMessageDialogComponent

        QGCSimpleMessageDialog {
        }
    }

    property bool _forceClose: false

    function finishCloseProcess() {
        _forceClose = true
        // For some reason on the Qml side Qt doesn't automatically disconnect a signal when an object is destroyed.
        // So we have to do it ourselves otherwise the signal flows through on app shutdown to an object which no longer exists.
        firstRunPromptManager.clearNextPromptSignal()
        QGroundControl.linkManager.shutdown()
        QGroundControl.videoManager.stopVideo();
        mainWindow.close()
    }

    // Check for things which should prevent the app from closing
    //  Returns true if it is OK to close
    readonly property int _skipUnsavedMissionCheckMask: 0x01
    readonly property int _skipPendingParameterWritesCheckMask: 0x02
    readonly property int _skipActiveConnectionsCheckMask: 0x04
    property int _closeChecksToSkip: 0
    function performCloseChecks() {
        if (!(_closeChecksToSkip & _skipUnsavedMissionCheckMask) && !checkForUnsavedMission()) {
            return false
        }
        if (!(_closeChecksToSkip & _skipPendingParameterWritesCheckMask) && !checkForPendingParameterWrites()) {
            return false
        }
        if (!(_closeChecksToSkip & _skipActiveConnectionsCheckMask) && !checkForActiveConnections()) {
            return false
        }
        finishCloseProcess()
        return true
    }

    property string closeDialogTitle: qsTr("Close %1").arg(QGroundControl.appName)

    function checkForUnsavedMission() {
        if (planView._planMasterController.dirty) {
            showMessageDialog(closeDialogTitle,
                              qsTr("You have a mission edit in progress which has not been saved/sent. If you close you will lose changes. Are you sure you want to close?"),
                              Dialog.Yes | Dialog.No,
                              function() { _closeChecksToSkip |= _skipUnsavedMissionCheckMask; performCloseChecks() })
            return false
        } else {
            return true
        }
    }

    function checkForPendingParameterWrites() {
        for (var index=0; index<QGroundControl.multiVehicleManager.vehicles.count; index++) {
            if (QGroundControl.multiVehicleManager.vehicles.get(index).parameterManager.pendingWrites) {
                mainWindow.showMessageDialog(closeDialogTitle,
                    qsTr("You have pending parameter updates to a vehicle. If you close you will lose changes. Are you sure you want to close?"),
                    Dialog.Yes | Dialog.No,
                    function() { _closeChecksToSkip |= _skipPendingParameterWritesCheckMask; performCloseChecks() })
                return false
            }
        }
        return true
    }

    function checkForActiveConnections() {
        if (QGroundControl.multiVehicleManager.activeVehicle) {
            mainWindow.showMessageDialog(closeDialogTitle,
                qsTr("There are still active connections to vehicles. Are you sure you want to exit?"),
                Dialog.Yes | Dialog.No,
                function() { _closeChecksToSkip |= _skipActiveConnectionsCheckMask; performCloseChecks() })
            return false
        } else {
            return true
        }
    }

    onClosing: (close) => {
        if (!_forceClose) {
            _closeChecksToSkip = 0
            close.accepted = performCloseChecks()
        }
    }

    background: Rectangle {
        anchors.fill:   parent
        color:          QGroundControl.globalPalette.window
    }

    FlyView { 
        id:                     flyView
        anchors.fill:           parent
        utmspSendActTrigger:    _utmspSendActTrigger
        enabled:                mainWindow._showFlyView
        visible:                opacity > 0
        opacity:                mainWindow._showFlyView ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: mainWindow._reducedMotionEnabled ? 0 : (ScreenTools.interactionAnimationDuration + 20)
                easing.type: Easing.InOutQuad
            }
        }
    }

    PlanView {
        id:             planView
        anchors.fill:   parent
        enabled:        !mainWindow._showFlyView
        visible:        opacity > 0
        opacity:        mainWindow._showFlyView ? 0 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: mainWindow._reducedMotionEnabled ? 0 : (ScreenTools.interactionAnimationDuration + 20)
                easing.type: Easing.InOutQuad
            }
        }
    }

    footer: LogReplayStatusBar {
        visible: QGroundControl.settingsManager.flyViewSettings.showLogReplayStatusBar.rawValue
    }

    MessageDialog {
        id:                 showTouchAreasNotification
        title:              qsTr("Debug Touch Areas")
        text:               qsTr("Touch Area display toggled")
        buttons:            MessageDialog.Ok
    }

    MessageDialog {
        id:                 advancedModeOnConfirmation
        title:              qsTr("Advanced Mode")
        text:               QGroundControl.corePlugin.showAdvancedUIMessage
        buttons:            MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function (button, role) {
            if (button === MessageDialog.Yes) {
                QGroundControl.corePlugin.showAdvancedUI = true
            }
        }
    }

    MessageDialog {
        id:                 advancedModeOffConfirmation
        title:              qsTr("Advanced Mode")
        text:               qsTr("Turn off Advanced Mode?")
        buttons:            MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function (button, role) {
            if (button === MessageDialog.Yes) {
                QGroundControl.corePlugin.showAdvancedUI = false
            }
        }
    }

    Drawer {
        id:             notificationDrawer
        edge:           Qt.RightEdge
        y:              ScreenTools.toolbarHeight
        width:          Math.min(ScreenTools.defaultFontPixelWidth * 46, mainWindow.width * 0.42)
        height:         mainWindow.height - y
        modal:          false
        interactive:    true

        onOpened: {
            if (_activeVehicle) {
                _activeVehicle.resetAllMessages()
            }
            _markAllTimelineNotificationsRead()
        }

        background: Rectangle {
            color:          qgcPal.window
            border.width:   1
            border.color:   qgcPal.groupBorder
        }

        contentItem: Item {
            anchors.fill: parent

            VehicleStatusDrawerContent {
                anchors.fill: parent
                drawer:       notificationDrawer
            }
        }
    }

    Drawer {
        id:             toolSelectDrawer
        edge:           Qt.RightEdge
        y:              ScreenTools.toolbarHeight
        padding:        ScreenTools.defaultFontPixelHeight * 0.5
        width:          Math.min((toolSelectDrawerLoader.item ? toolSelectDrawerLoader.item.implicitWidth : ScreenTools.defaultFontPixelWidth * 30) + (padding * 2), mainWindow.width * 0.6)
        height:         Math.min((toolSelectDrawerLoader.item ? toolSelectDrawerLoader.item.implicitHeight : ScreenTools.defaultFontPixelHeight * 20) + (padding * 2), mainWindow.height - y)
        modal:          false
        interactive:    true

        background: Rectangle {
            color:          qgcPal.window
            border.width:   1
            border.color:   qgcPal.groupBorder
        }

        contentItem: Loader {
            id:                 toolSelectDrawerLoader
            sourceComponent:    toolSelectComponent

            Binding {
                target:     toolSelectDrawerLoader.item
                property:   "drawer"
                value:      toolSelectDrawer
            }
        }
    }

    function showToolSelectDialog() {
        if (!mainWindow.allowViewSwitch()) {
            return
        }

        if (toolSelectDrawer.visible) {
            toolSelectDrawer.close()
        } else {
            _dismissFlyViewControlsPopup()
            if (notificationDrawer.visible) {
                notificationDrawer.close()
            }
            if (indicatorDrawer.visible) {
                closeIndicatorDrawer()
            }
            toolSelectDrawer.open()
        }
    }

    function closeToolSelectDialog() {
        toolSelectDrawer.close()
    }

    Component {
        id: toolSelectComponent

        ToolIndicatorPage {
            id:         toolSelectDialog
            //title:      qsTr("Select Tool")

            property real _toolButtonHeight:    ScreenTools.defaultFontPixelHeight * 3
            property real _margins:             ScreenTools.defaultFontPixelWidth

            contentComponent: Component {
                ColumnLayout {
                    width:  innerLayout.width + (toolSelectDialog._margins * 2)
                    height: innerLayout.height + (toolSelectDialog._margins * 2)

                    ColumnLayout {
                        id:             innerLayout
                        Layout.margins: toolSelectDialog._margins
                        spacing:        ScreenTools.defaultFontPixelWidth

                        SubMenuButton {
                            id:                 analyzeButton
                            height:             toolSelectDialog._toolButtonHeight
                            Layout.fillWidth:   true
                            text:               qsTr("Analyze Tools")
                            imageResource:      "/qmlimages/Analyze.svg"
                            visible:            QGroundControl.corePlugin.showAdvancedUI
                            onClicked: {
                                if (mainWindow.allowViewSwitch()) {
                                    mainWindow.closeToolSelectDialog()
                                    mainWindow.showAnalyzeTool()
                                }
                            }
                        }

                        SubMenuButton {
                            id:                 setupButton
                            height:             toolSelectDialog._toolButtonHeight
                            Layout.fillWidth:   true
                            text:               qsTr("Vehicle Configuration")
                            imageResource:      "/qmlimages/Gears.svg"
                            onClicked: {
                                if (mainWindow.allowViewSwitch()) {
                                    mainWindow.closeToolSelectDialog()
                                    mainWindow.showVehicleConfig()
                                }
                            }
                        }

                        SubMenuButton {
                            id:                 settingsButton
                            height:             toolSelectDialog._toolButtonHeight
                            Layout.fillWidth:   true
                            text:               qsTr("Application Settings")
                            imageResource:      "/res/QGCLogoFull.svg"
                            imageColor:         "transparent"
                            visible:            !QGroundControl.corePlugin.options.combineSettingsAndSetup
                            onClicked: {
                                if (mainWindow.allowViewSwitch()) {
                                    mainWindow.closeToolSelectDialog()
                                    mainWindow.showSettingsTool()
                                }
                            }
                        }

                        SubMenuButton {
                            id:                 closeButton
                            height:             toolSelectDialog._toolButtonHeight
                            Layout.fillWidth:   true
                            text:               qsTr("Close %1").arg(QGroundControl.appName)
                            imageResource:      "/res/cancel.svg"
                            visible:            mainWindow.visibility === Window.FullScreen
                            onClicked: {
                                if (mainWindow.allowViewSwitch()) {
                                    mainWindow.finishCloseProcess()
                                }
                            }
                        }

                        ColumnLayout {
                            width:                  innerLayout.width
                            spacing:                0
                            Layout.alignment:       Qt.AlignHCenter

                            QGCLabel {
                                id:                     versionLabel
                                text:                   qsTr("%1 Version").arg(QGroundControl.appName)
                                font.pointSize:         ScreenTools.smallFontPointSize
                                wrapMode:               QGCLabel.WordWrap
                                Layout.maximumWidth:    parent.width
                                Layout.alignment:       Qt.AlignHCenter
                            }

                            QGCLabel {
                                text:                   QGroundControl.qgcVersion
                                font.pointSize:         ScreenTools.smallFontPointSize
                                wrapMode:               QGCLabel.WrapAnywhere
                                Layout.maximumWidth:    parent.width
                                Layout.alignment:       Qt.AlignHCenter

                                QGCMouseArea {
                                    id:                 easterEggMouseArea
                                    anchors.topMargin:  -versionLabel.height
                                    anchors.fill:       parent

                                    onClicked: (mouse) => {
                                        if (mouse.modifiers & Qt.ControlModifier) {
                                            QGroundControl.corePlugin.showTouchAreas = !QGroundControl.corePlugin.showTouchAreas
                                            showTouchAreasNotification.open()
                                        } else if (ScreenTools.isMobile || mouse.modifiers & Qt.ShiftModifier) {
                                            mainWindow.closeToolSelectDialog()
                                            if(!QGroundControl.corePlugin.showAdvancedUI) {
                                                advancedModeOnConfirmation.open()
                                            } else {
                                                advancedModeOffConfirmation.open()
                                            }
                                        }
                                    }

                                    // This allows you to change this on mobile
                                    onPressAndHold: {
                                        QGroundControl.corePlugin.showTouchAreas = !QGroundControl.corePlugin.showTouchAreas
                                        showTouchAreasNotification.open()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id:             toolDrawer
        anchors.fill:   parent
        visible:        false
        color:          qgcPal.window

        property var backIcon
        property string toolTitle
        property alias toolSource:  toolDrawerLoader.source
        property var toolIcon

        onVisibleChanged: {
            if (!toolDrawer.visible) {
                toolDrawerLoader.source = ""
            }
        }

        // This need to block click event leakage to underlying map.
        DeadMouseArea {
            anchors.fill: parent
        }

        Rectangle {
            id:             toolDrawerToolbar
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    parent.top
            height:         ScreenTools.toolbarHeight
            color:          qgcPal.toolbarBackground

            RowLayout {
                id:                 toolDrawerToolbarLayout
                anchors.leftMargin: ScreenTools.defaultFontPixelWidth
                anchors.left:       parent.left
                anchors.top:        parent.top
                anchors.bottom:     parent.bottom
                spacing:            ScreenTools.defaultFontPixelWidth

                QGCLabel {
                    font.pointSize: ScreenTools.largeFontPointSize
                    text:           "<"
                }

                QGCLabel {
                    id:             toolbarDrawerText
                    text:           qsTr("Exit") + " " + toolDrawer.toolTitle
                    font.pointSize: ScreenTools.largeFontPointSize
                }
            }

            QGCMouseArea {
                anchors.fill: toolDrawerToolbarLayout
                onClicked: {
                    if (mainWindow.allowViewSwitch()) {
                        toolDrawer.visible = false
                    }
                }
            }
        }

        Loader {
            id:             toolDrawerLoader
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    toolDrawerToolbar.bottom
            anchors.bottom: parent.bottom

            Connections {
                target:                 toolDrawerLoader.item
                ignoreUnknownSignals:   true
                onPopout:               toolDrawer.visible = false
            }
        }
    }

    //-------------------------------------------------------------------------
    //-- Critical Vehicle Message Popup

    function showCriticalVehicleMessage(message) {
        closeIndicatorDrawer()
        closeToolSelectDialog()
        if (criticalVehicleMessagePopup.visible || QGroundControl.videoManager.fullScreen) {
            // We received additional warning message while an older warning message was still displayed.
            // When the user close the older one drop the message indicator tool so they can see the rest of them.
            criticalVehicleMessagePopup.additionalCriticalMessagesReceived = true
        } else {
            criticalVehicleMessagePopup.criticalVehicleMessage      = message
            criticalVehicleMessagePopup.additionalCriticalMessagesReceived = false
            criticalVehicleMessagePopup.open()
        }
    }

    Popup {
        id:                 criticalVehicleMessagePopup
        y:                  ScreenTools.toolbarHeight + ScreenTools.defaultFontPixelHeight
        x:                  Math.round((mainWindow.width - width) * 0.5)
        width:              mainWindow.width  * 0.55
        height:             criticalVehicleMessageText.contentHeight + ScreenTools.defaultFontPixelHeight * 2
        modal:              false
        focus:              true

        property alias  criticalVehicleMessage:             criticalVehicleMessageText.text
        property bool   additionalCriticalMessagesReceived: false

        background: Rectangle {
            anchors.fill:   parent
            color:          qgcPal.alertBackground
            radius:         ScreenTools.defaultFontPixelHeight * 0.5
            border.color:   qgcPal.alertBorder
            border.width:   2

            Rectangle {
                anchors.horizontalCenter:   parent.horizontalCenter
                anchors.top:                parent.top
                anchors.topMargin:          -(height / 2)
                color:                      qgcPal.alertBackground
                radius:                     ScreenTools.defaultFontPixelHeight * 0.25
                border.color:               qgcPal.alertBorder
                border.width:               1
                width:                      vehicleWarningLabel.contentWidth + _margins
                height:                     vehicleWarningLabel.contentHeight + _margins

                property real _margins: ScreenTools.defaultFontPixelHeight * 0.25

                QGCLabel {
                    id:                 vehicleWarningLabel
                    anchors.centerIn:   parent
                    text:               qsTr("Vehicle Error")
                    font.pointSize:     ScreenTools.smallFontPointSize
                    color:              qgcPal.alertText
                }
            }

            Rectangle {
                id:                         additionalErrorsIndicator
                anchors.horizontalCenter:   parent.horizontalCenter
                anchors.bottom:             parent.bottom
                anchors.bottomMargin:       -(height / 2)
                color:                      qgcPal.alertBackground
                radius:                     ScreenTools.defaultFontPixelHeight * 0.25
                border.color:               qgcPal.alertBorder
                border.width:               1
                width:                      additionalErrorsLabel.contentWidth + _margins
                height:                     additionalErrorsLabel.contentHeight + _margins
                visible:                    criticalVehicleMessagePopup.additionalCriticalMessagesReceived

                property real _margins: ScreenTools.defaultFontPixelHeight * 0.25

                QGCLabel {
                    id:                 additionalErrorsLabel
                    anchors.centerIn:   parent
                    text:               qsTr("Additional errors received")
                    font.pointSize:     ScreenTools.smallFontPointSize
                    color:              qgcPal.alertText
                }
            }
        }

        QGCLabel {
            id:                 criticalVehicleMessageText
            width:              criticalVehicleMessagePopup.width - ScreenTools.defaultFontPixelHeight
            anchors.centerIn:   parent
            wrapMode:           Text.WordWrap
            color:              qgcPal.alertText
            textFormat:         TextEdit.RichText
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                criticalVehicleMessagePopup.close()
                if (criticalVehicleMessagePopup.additionalCriticalMessagesReceived) {
                    criticalVehicleMessagePopup.additionalCriticalMessagesReceived = false;
                    flyView.dropMainStatusIndicatorTool();
                } else {
                    QGroundControl.multiVehicleManager.activeVehicle.resetErrorLevelMessages();
                }
            }
        }
    }

    Popup {
        id:                 transientTopNoticePopup
        y:                  ScreenTools.toolbarHeight + (ScreenTools.defaultFontPixelHeight * 0.55)
        x:                  Math.round((mainWindow.width - width) * 0.5) + _shakeOffset
        width:              Math.min(mainWindow.width * 0.46, ScreenTools.defaultFontPixelWidth * 52)
        height:             transientTopNoticeContent.implicitHeight + (ScreenTools.defaultFontPixelHeight * 0.9)
        padding:            0
        modal:              false
        focus:              false
        closePolicy:        Popup.NoAutoClose

        property string noticeTitle:      ""
        property string noticeText:       ""
        property string noticeSeverity:   "info"
        property int    noticeDurationMs: 4200
        property real   _shakeOffset:     0

        function present() {
            topNoticeCloseTimer.stop()
            if (!opened) {
                open()
            }
            _shakeOffset = 0
            if (!mainWindow._reducedMotionEnabled) {
                topNoticeShakeAnimation.restart()
            }
            topNoticeCloseTimer.interval = Math.max(2200, noticeDurationMs)
            topNoticeCloseTimer.restart()
        }

        onClosed: {
            _shakeOffset = 0
            topNoticeCloseTimer.stop()
        }

        background: Rectangle {
            anchors.fill:       parent
            color:              Qt.rgba(
                                    mainWindow._transientNoticeAccentColor(transientTopNoticePopup.noticeSeverity).r,
                                    mainWindow._transientNoticeAccentColor(transientTopNoticePopup.noticeSeverity).g,
                                    mainWindow._transientNoticeAccentColor(transientTopNoticePopup.noticeSeverity).b,
                                    0.14
                                )
            radius:             ScreenTools.defaultFontPixelHeight * 0.46
            border.width:       1
            border.color:       mainWindow._transientNoticeAccentColor(transientTopNoticePopup.noticeSeverity)
        }

        contentItem: Item {
            implicitHeight: transientTopNoticeContent.implicitHeight + (ScreenTools.defaultFontPixelHeight * 0.9)

            RowLayout {
                id:                     transientTopNoticeContent
                anchors.fill:           parent
                anchors.leftMargin:     ScreenTools.defaultFontPixelWidth * 0.9
                anchors.rightMargin:    ScreenTools.defaultFontPixelWidth * 0.9
                anchors.topMargin:      ScreenTools.defaultFontPixelHeight * 0.45
                anchors.bottomMargin:   ScreenTools.defaultFontPixelHeight * 0.45
                spacing:                ScreenTools.defaultFontPixelWidth * 0.8

                Rectangle {
                    Layout.alignment:    Qt.AlignTop
                    width:               ScreenTools.defaultFontPixelHeight * 1.2
                    height:              width
                    radius:              width / 2
                    color:               Qt.rgba(
                                            mainWindow._transientNoticeAccentColor(transientTopNoticePopup.noticeSeverity).r,
                                            mainWindow._transientNoticeAccentColor(transientTopNoticePopup.noticeSeverity).g,
                                            mainWindow._transientNoticeAccentColor(transientTopNoticePopup.noticeSeverity).b,
                                            0.18
                                        )
                    border.width:        1
                    border.color:        mainWindow._transientNoticeAccentColor(transientTopNoticePopup.noticeSeverity)

                    QGCLabel {
                        anchors.centerIn:   parent
                        text:               mainWindow._transientNoticeGlyph(transientTopNoticePopup.noticeSeverity)
                        font.pointSize:     ScreenTools.defaultFontPointSize
                        font.weight:        Font.DemiBold
                        color:              mainWindow._transientNoticeAccentColor(transientTopNoticePopup.noticeSeverity)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth:   true
                    spacing:            ScreenTools.defaultFontPixelHeight * 0.12

                    QGCLabel {
                        Layout.fillWidth:   true
                        text:               transientTopNoticePopup.noticeTitle
                        font.pointSize:     ScreenTools.smallFontPointSize
                        font.weight:        Font.DemiBold
                        color:              mainWindow._transientNoticeAccentColor(transientTopNoticePopup.noticeSeverity)
                        elide:              Text.ElideRight
                    }

                    QGCLabel {
                        Layout.fillWidth:   true
                        text:               transientTopNoticePopup.noticeText
                        font.pointSize:     ScreenTools.defaultFontPointSize
                        wrapMode:           Text.WordWrap
                        maximumLineCount:   2
                        elide:              Text.ElideRight
                        color:              mainWindow._transientNoticeAccentColor(transientTopNoticePopup.noticeSeverity)
                    }
                }
            }
        }

        enter: Transition {
            NumberAnimation {
                property:   "opacity"
                from:       0
                to:         1
                duration:   mainWindow._reducedMotionEnabled ? 0 : (ScreenTools.interactionAnimationDuration + 40)
                easing.type: Easing.OutCubic
            }
        }

        exit: Transition {
            NumberAnimation {
                property:   "opacity"
                from:       1
                to:         0
                duration:   mainWindow._reducedMotionEnabled ? 0 : ScreenTools.interactionAnimationDuration
                easing.type: Easing.InCubic
            }
        }

        Timer {
            id:         topNoticeCloseTimer
            interval:   transientTopNoticePopup.noticeDurationMs
            repeat:     false
            onTriggered: transientTopNoticePopup.close()
        }

        SequentialAnimation {
            id: topNoticeShakeAnimation
            running: false

            NumberAnimation { target: transientTopNoticePopup; property: "_shakeOffset"; to: -10; duration: 55; easing.type: Easing.OutQuad }
            NumberAnimation { target: transientTopNoticePopup; property: "_shakeOffset"; to: 10; duration: 75; easing.type: Easing.InOutQuad }
            NumberAnimation { target: transientTopNoticePopup; property: "_shakeOffset"; to: -7; duration: 65; easing.type: Easing.InOutQuad }
            NumberAnimation { target: transientTopNoticePopup; property: "_shakeOffset"; to: 7; duration: 65; easing.type: Easing.InOutQuad }
            NumberAnimation { target: transientTopNoticePopup; property: "_shakeOffset"; to: 0; duration: 55; easing.type: Easing.OutQuad }
        }

        MouseArea {
            anchors.fill:   parent
            hoverEnabled:   true
            onClicked:      transientTopNoticePopup.close()
        }
    }

    //-------------------------------------------------------------------------
    //-- Indicator Drawer

    function showIndicatorDrawer(drawerComponent, indicatorItem) {
        _dismissFlyViewControlsPopup()
        indicatorDrawer.sourceComponent = drawerComponent
        indicatorDrawer.indicatorItem = indicatorItem
        indicatorDrawer.open()
    }

    function closeIndicatorDrawer() {
        indicatorDrawer.close()
    }

    Popup {
        id:             indicatorDrawer
        x:              calcXPosition()
        y:              ScreenTools.toolbarHeight + _margins
        leftInset:      0
        rightInset:     0
        topInset:       0
        bottomInset:    0
        padding:        _margins * 2
        visible:        false
        modal:          true
        focus:          true
        closePolicy:    Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property var sourceComponent
        property var indicatorItem

        property bool _expanded:    false
        property real _margins:     ScreenTools.defaultFontPixelHeight / 4

        function calcXPosition() {
            if (indicatorItem) {
                var xCenter = indicatorItem.mapToItem(mainWindow.contentItem, indicatorItem.width / 2, 0).x
                return Math.max(_margins, Math.min(xCenter - (contentItem.implicitWidth / 2), mainWindow.contentItem.width - contentItem.implicitWidth - _margins - (indicatorDrawer.padding * 2) - (ScreenTools.defaultFontPixelHeight / 2)))
            } else {
                return _margins
            }
        }

        onOpened: {
            _expanded                               = false;
            indicatorDrawerLoader.sourceComponent   = indicatorDrawer.sourceComponent
        }
        onClosed: {
            _expanded                               = false
            indicatorItem                           = undefined
            indicatorDrawerLoader.sourceComponent   = undefined
        }

        background: Item {
            Rectangle {
                id:             backgroundRect
                anchors.fill:   parent
                color:          QGroundControl.globalPalette.window
                radius:         indicatorDrawer._margins
                opacity:        0.85
            }

            Rectangle {
                anchors.horizontalCenter:   backgroundRect.right
                anchors.verticalCenter:     backgroundRect.top
                width:                      ScreenTools.largeFontPixelHeight
                height:                     width
                radius:                     width / 2
                color:                      QGroundControl.globalPalette.button
                border.color:               QGroundControl.globalPalette.buttonText
                visible:                    indicatorDrawerLoader.item && indicatorDrawerLoader.item.showExpand && !indicatorDrawer._expanded

                QGCLabel {
                    anchors.centerIn:   parent
                    text:               ">"
                    color:              QGroundControl.globalPalette.buttonText
                }  

                QGCMouseArea {
                    fillItem: parent
                    onClicked: indicatorDrawer._expanded = true
                }
            }
        }

        contentItem: QGCFlickable {
            id:             indicatorDrawerLoaderFlickable
            implicitWidth:  Math.min(mainWindow.contentItem.width - (2 * indicatorDrawer._margins) - (indicatorDrawer.padding * 2), indicatorDrawerLoader.width)
            implicitHeight: Math.min(mainWindow.contentItem.height - ScreenTools.toolbarHeight - (2 * indicatorDrawer._margins) - (indicatorDrawer.padding * 2), indicatorDrawerLoader.height)
            contentWidth:   indicatorDrawerLoader.width
            contentHeight:  indicatorDrawerLoader.height

            Loader {
                id: indicatorDrawerLoader

                Binding {
                    target:     indicatorDrawerLoader.item
                    property:   "expanded"
                    value:      indicatorDrawer._expanded
                }

                Binding {
                    target:     indicatorDrawerLoader.item
                    property:   "drawer"
                    value:      indicatorDrawer
                }
            }
        }
    }

    // We have to create the popup windows for the Analyze pages here so that the creation context is rooted
    // to mainWindow. Otherwise if they are rooted to the AnalyzeView itself they will die when the analyze viewSwitch
    // closes.

    function createrWindowedAnalyzePage(title, source) {
        var windowedPage = windowedAnalyzePage.createObject(mainWindow)
        windowedPage.title = title
        windowedPage.source = source
    }

    Component {
        id: windowedAnalyzePage

        Window {
            width:      ScreenTools.defaultFontPixelWidth  * 100
            height:     ScreenTools.defaultFontPixelHeight * 40
            visible:    true

            property alias source: loader.source

            Rectangle {
                color:          QGroundControl.globalPalette.window
                anchors.fill:   parent

                Loader {
                    id:             loader
                    anchors.fill:   parent
                    onLoaded:       item.popped = true
                }
            }

            onClosing: {
                visible = false
                source = ""
            }
        }
    }

    Connections{
         target: activationbar
         function onActivationTriggered(value){
              _utmspSendActTrigger= value
         }
    }

    UTMSPActivationStatusBar{
         id:                         activationbar
         activationStartTimestamp:   UTMSPStateStorage.startTimeStamp
         activationApproval:         UTMSPStateStorage.showActivationTab && QGroundControl.utmspManager.utmspVehicle.vehicleActivation
         flightID:                   UTMSPStateStorage.flightID
         anchors.fill:               parent
    }
}
