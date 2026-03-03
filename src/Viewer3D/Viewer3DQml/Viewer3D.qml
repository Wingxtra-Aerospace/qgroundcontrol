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
        }
    }

    // If streaming flag flips while open, close/reopen streaming path accordingly
    on_Streaming3DEnabledChanged: {
        if (_streaming3DEnabled !== true) {
            _finalizeClose(true, false)
            return
        }

        if (!isOpen) {
            return
        }

        _setStreamingActive(true)
        if (_streamingNeedsMapSyncOnOpen && _sync2DMapToStreaming3D()) {
            _streamingNeedsMapSyncOnOpen = false
        }
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

    Connections {
        target: QGroundControl
        enabled: _streaming3DEnabled === true

        function onFlightMapPositionChanged() {
            viewer3DBody._markStreaming2DMapDirty()
        }

        function onFlightMapZoomChanged() {
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
