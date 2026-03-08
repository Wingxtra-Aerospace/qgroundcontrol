import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Controllers
import QGroundControl.FactSystem
import QGroundControl.FlightDisplay
import QGroundControl.FlightMap
import QGroundControl.Palette
import QGroundControl.ScreenTools
import QGroundControl.Vehicle

Item {
    id: viewer3DBody

    // FlyView expects these to exist and behave consistently
    property bool isOpen: false
    property Item pipView: null
    property Item pipState: _pipState
    property var missionController: null
    property bool isSatelliteMap: true
    property var _flyViewSettings: QGroundControl.settingsManager.flyViewSettings
    readonly property real minimumZoomLevel: 2.0
    readonly property real maximumZoomLevel: 20.0
    property real zoomLevel: _clampZoom(Number(QGroundControl.flightMapZoom))
    property bool followVehicleEnabled: _flyViewSettings ? _flyViewSettings.keepMapCenteredOnVehicle.rawValue : false
    property bool declutterEnabled: false
    property var _activeVehicle: QGroundControl.multiVehicleManager.activeVehicle
    property bool canCenterVehicle: !!(_activeVehicle && _activeVehicle.coordinate && _activeVehicle.coordinate.isValid)

    // Existing setting: Fly View -> 3D View enabled
    property bool _viewer3DEnabled: QGroundControl.settingsManager.viewer3DSettings.enabled.rawValue

    // Global feature flag controlled from C++
    property bool _streaming3DEnabled: QGroundControl.streaming3DEnabled

    // Error shown over the 3D area if streaming fails to load
    property string _streamingLoadError: ""
    property bool _streamingCloseSyncPending: false
    property bool _streamingNeedsMapSyncOnOpen: true
    property var _streamingLastClosedMapState: null

    PipState {
        id: _pipState
        pipView: viewer3DBody.pipView
        isDark: true
    }

    function _setStreamingActive(active) {
        streaming3DLoader.active = active
        if (!active) {
            _streamingLoadError = ""
        }
    }

    function _clampZoom(zoomValue) {
        const zoom = Number(zoomValue)
        if (!isFinite(zoom)) {
            return minimumZoomLevel
        }
        return Math.max(minimumZoomLevel, Math.min(maximumZoomLevel, zoom))
    }

    function stepZoom(zoomDelta) {
        const delta = Number(zoomDelta)
        if (!isFinite(delta) || delta === 0) {
            return
        }

        const clampedZoom = _clampZoom(Number(zoomLevel) + delta)
        if (Math.abs(clampedZoom - Number(zoomLevel)) < 1e-4) {
            return
        }

        zoomLevel = clampedZoom
    }

    function _pushZoomToStreaming3D() {
        if (!isOpen || _streaming3DEnabled !== true) {
            return false
        }

        if (streaming3DLoader.status === Loader.Ready &&
                streaming3DLoader.item &&
                typeof streaming3DLoader.item.setZoomLevel === "function") {
            streaming3DLoader.item.setZoomLevel(_clampZoom(zoomLevel))
            return true
        }

        return false
    }

    function _pushFollowStateToStreaming3D() {
        if (_streaming3DEnabled !== true) {
            return false
        }

        if (streaming3DLoader.status === Loader.Ready &&
                streaming3DLoader.item &&
                typeof streaming3DLoader.item.setFollowVehicleEnabled === "function") {
            return streaming3DLoader.item.setFollowVehicleEnabled(followVehicleEnabled)
        }

        return false
    }

    function _pushDeclutterStateToStreaming3D() {
        if (_streaming3DEnabled !== true) {
            return false
        }

        if (streaming3DLoader.status === Loader.Ready &&
                streaming3DLoader.item &&
                typeof streaming3DLoader.item.setDeclutterEnabled === "function") {
            return streaming3DLoader.item.setDeclutterEnabled(declutterEnabled)
        }

        return false
    }

    function toggleFollowVehicle() {
        const followVehicle = !followVehicleEnabled
        if (_flyViewSettings && _flyViewSettings.keepMapCenteredOnVehicle) {
            _flyViewSettings.keepMapCenteredOnVehicle.rawValue = followVehicle
        } else {
            followVehicleEnabled = followVehicle
        }
        _pushFollowStateToStreaming3D()
        if (followVehicle) {
            centerOnActiveVehicle()
        }
    }

    function toggleDeclutter() {
        declutterEnabled = !declutterEnabled
        _pushDeclutterStateToStreaming3D()
    }

    function centerOnActiveVehicle() {
        if (!canCenterVehicle || _streaming3DEnabled !== true) {
            return
        }

        if (streaming3DLoader.status === Loader.Ready &&
                streaming3DLoader.item &&
                typeof streaming3DLoader.item.centerOnActiveVehicle === "function") {
            streaming3DLoader.item.centerOnActiveVehicle()
        }
    }

    function getScaleLineMeters(scaleLinePixelLength, yPixel, onDone) {
        if (_streaming3DEnabled !== true) {
            if (onDone) {
                onDone(Number.NaN)
            }
            return false
        }

        if (streaming3DLoader.status === Loader.Ready &&
                streaming3DLoader.item &&
                typeof streaming3DLoader.item.getScaleLineMeters === "function") {
            return streaming3DLoader.item.getScaleLineMeters(scaleLinePixelLength, yPixel, onDone)
        }

        if (onDone) {
            onDone(Number.NaN)
        }
        return false
    }

    function _prewarmStreaming3D() {
        if (_viewer3DEnabled !== true || _streaming3DEnabled !== true) {
            return
        }

        if (streaming3DLoader.active !== true) {
            console.log("[Viewer3D] prewarming streaming 3D loader")
            _setStreamingActive(true)
        }
    }

    function _sync2DMapToStreaming3D() {
        if (_streaming3DEnabled !== true) {
            return false
        }

        if (streaming3DLoader.status === Loader.Ready &&
                streaming3DLoader.item &&
                typeof streaming3DLoader.item.syncFrom2DMapTo3D === "function") {
            streaming3DLoader.item.syncFrom2DMapTo3D()
            return true
        }

        return false
    }

    function _captureCurrent2DMapState() {
        const mapCoordinate = QGroundControl.flightMapPosition
        if (!mapCoordinate || !mapCoordinate.isValid) {
            return null
        }

        return {
            latitude: Number(mapCoordinate.latitude),
            longitude: Number(mapCoordinate.longitude),
            zoom: Number(QGroundControl.flightMapZoom)
        }
    }

    function _isSameMapState(lhs, rhs) {
        if (!lhs || !rhs) {
            return false
        }

        return Math.abs(Number(lhs.latitude) - Number(rhs.latitude)) < 1e-7 &&
            Math.abs(Number(lhs.longitude) - Number(rhs.longitude)) < 1e-7 &&
            Math.abs(Number(lhs.zoom) - Number(rhs.zoom)) < 1e-4
    }

    function _markStreaming2DMapDirty() {
        if (_streaming3DEnabled !== true || isOpen) {
            return
        }

        const currentMapState = _captureCurrent2DMapState()
        if (!currentMapState) {
            _streamingLastClosedMapState = null
            _streamingNeedsMapSyncOnOpen = true
            return
        }

        // Ignore signal echoes from close() sync write-back if state is unchanged.
        if (_isSameMapState(_streamingLastClosedMapState, currentMapState)) {
            return
        }

        _streamingLastClosedMapState = null
        _streamingNeedsMapSyncOnOpen = true
    }

    function _finalizeClose(forceUnloadStreaming, preservePoseFrom3D) {
        _streamingCloseSyncPending = false
        streamingCloseSyncSafetyTimer.stop()
        isOpen = false

        // Keep streaming view alive across 2D/3D toggles to avoid full reload.
        // Unload only when explicitly requested (for example, disabling 3D).
        if (forceUnloadStreaming === true || _streaming3DEnabled !== true) {
            _setStreamingActive(false)
        }

        if (forceUnloadStreaming === true || _streaming3DEnabled !== true || preservePoseFrom3D !== true) {
            _streamingNeedsMapSyncOnOpen = true
            _streamingLastClosedMapState = null
        } else {
            _streamingNeedsMapSyncOnOpen = false
            _streamingLastClosedMapState = _captureCurrent2DMapState()
        }

        _streamingLoadError = ""
    }

    function open() {
        if (_viewer3DEnabled !== true) {
            return
        }

        if (_streaming3DEnabled !== true) {
            _streamingLoadError = "Streaming 3D is disabled in this build."
            return
        }

        isOpen = true
        console.log("[Viewer3D] open() enabled=", _viewer3DEnabled, "streaming=", _streaming3DEnabled)

        _setStreamingActive(true)

        if (_streamingNeedsMapSyncOnOpen && _sync2DMapToStreaming3D()) {
            _streamingNeedsMapSyncOnOpen = false
        }

        if (streaming3DLoader.status === Loader.Ready &&
                streaming3DLoader.item &&
                typeof streaming3DLoader.item.activate === "function") {
            streaming3DLoader.item.activate()
        }
    }

    function close() {
        if (_streaming3DEnabled === true &&
                streaming3DLoader.status === Loader.Ready &&
                streaming3DLoader.item &&
                typeof streaming3DLoader.item.syncFrom3DTo2DMap === "function") {
            _streamingCloseSyncPending = true
            streamingCloseSyncSafetyTimer.restart()
            streaming3DLoader.item.syncFrom3DTo2DMap(function(synced) {
                if (!_streamingCloseSyncPending) {
                    return
                }
                _finalizeClose(false, synced === true)
            })
            return
        }

        _finalizeClose(false, false)
    }

    Timer {
        id: streamingCloseSyncSafetyTimer
        interval: 900
        repeat: false
        onTriggered: {
            if (viewer3DBody._streamingCloseSyncPending) {
                viewer3DBody._finalizeClose(false, false)
            }
        }
    }

    visible: isOpen
    enabled: isOpen

    // If user disables 3D in Settings while open, close everything cleanly
    on_Viewer3DEnabledChanged: {
        if (_viewer3DEnabled === false) {
            _finalizeClose(true, false)
            return
        }

        _prewarmStreaming3D()
    }

    // If streaming flag flips while open, close/reopen streaming path accordingly
    on_Streaming3DEnabledChanged: {
        if (_streaming3DEnabled !== true) {
            _finalizeClose(true, false)
            return
        }

        _prewarmStreaming3D()

        if (!isOpen) {
            return
        }

        _setStreamingActive(true)
        if (_streamingNeedsMapSyncOnOpen && _sync2DMapToStreaming3D()) {
            _streamingNeedsMapSyncOnOpen = false
        }
    }

    onFollowVehicleEnabledChanged: {
        _pushFollowStateToStreaming3D()
    }

    onDeclutterEnabledChanged: {
        _pushDeclutterStateToStreaming3D()
    }

    Component.onCompleted: {
        _prewarmStreaming3D()
    }

    Loader {
        id: streaming3DLoader
        anchors.fill: parent
        active: false
        source: "Viewer3DStreaming.qml"

        onStatusChanged: {
            if (status === Loader.Loading) {
                _streamingLoadError = ""
            } else if (status === Loader.Error) {
                _streamingLoadError = "Streaming 3D failed to load: " + errorString()
                console.log("[Streaming3D] Loader.Error:", errorString())
            } else if (status === Loader.Ready) {
                console.log("[Streaming3D] Loader.Ready")
                _streamingLoadError = ""
                _pushFollowStateToStreaming3D()
                _pushDeclutterStateToStreaming3D()
                if (isOpen && _streamingNeedsMapSyncOnOpen && _sync2DMapToStreaming3D()) {
                    _streamingNeedsMapSyncOnOpen = false
                }
            }
        }
    }

    Binding {
        target: streaming3DLoader.item
        property: "viewerOpen"
        value: isOpen
        when: (streaming3DLoader.status === Loader.Ready)
    }

    onZoomLevelChanged: {
        const clampedZoom = _clampZoom(zoomLevel)
        if (Math.abs(Number(zoomLevel) - clampedZoom) > 1e-4) {
            zoomLevel = clampedZoom
            return
        }

        if (Math.abs(Number(QGroundControl.flightMapZoom) - clampedZoom) > 1e-4) {
            QGroundControl.flightMapZoom = clampedZoom
        }

        _pushZoomToStreaming3D()
    }

    Binding {
        target: streaming3DLoader.item
        property: "missionController"
        value: viewer3DBody.missionController
        when: (streaming3DLoader.status === Loader.Ready)
    }

    Connections {
        target: streaming3DLoader.item
        enabled: (streaming3DLoader.status === Loader.Ready)
        ignoreUnknownSignals: true

        function onMapViewStatePolled(mapViewState) {
            if (!mapViewState) {
                return
            }

            const polledZoom = viewer3DBody._clampZoom(Number(mapViewState.zoom))
            if (Math.abs(Number(viewer3DBody.zoomLevel) - polledZoom) > 1e-4) {
                viewer3DBody.zoomLevel = polledZoom
            }
        }
    }

    Connections {
        target: QGroundControl
        enabled: _streaming3DEnabled === true

        function onFlightMapPositionChanged() {
            viewer3DBody._markStreaming2DMapDirty()
        }

        function onFlightMapZoomChanged() {
            const currentZoom = viewer3DBody._clampZoom(Number(QGroundControl.flightMapZoom))
            if (Math.abs(Number(viewer3DBody.zoomLevel) - currentZoom) > 1e-4) {
                viewer3DBody.zoomLevel = currentZoom
            }
            viewer3DBody._markStreaming2DMapDirty()
        }
    }

    // Error overlay
    Rectangle {
        anchors.fill: parent
        color: "#99000000"
        visible: isOpen && (_streamingLoadError.length > 0)
        z: 1000

        QGCLabel {
            anchors.centerIn: parent
            width: parent.width * 0.8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: _streamingLoadError
        }
    }
}
