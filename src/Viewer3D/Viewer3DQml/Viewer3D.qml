import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
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

import QGroundControl.Viewer3D
import Viewer3D.Models3D

/// @author Omid Esrafilian <esrafilian.omid@gmail.com>

Item {
    id: viewer3DBody

    // FlyView expects these to exist and behave consistently
    property bool isOpen: false
    property Item pipView: null
    property Item pipState: _pipState

    // Existing setting: Fly View -> 3D View enabled
    property bool _viewer3DEnabled: QGroundControl.settingsManager.viewer3DSettings.enabled.rawValue

    // New streaming feature flag (C++ global you added)
    // Must be true to use the streaming loader
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

    function _setLegacyActive(active) {
        // Legacy OSM viewer path
        view3DManagerLoader.active = active
        if (!active) {
            view3DLoader.active = false
        }
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
        _setLegacyActive(false)

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
        // Only open if the setting is enabled
        if (_viewer3DEnabled !== true) {
            return
        }

        isOpen = true

        console.log("[Viewer3D] open() enabled=", _viewer3DEnabled, "streaming=", _streaming3DEnabled)

        // Choose one path ONLY
        if (_streaming3DEnabled === true) {
            _setLegacyActive(false)
            _setStreamingActive(true)
            if (_streamingNeedsMapSyncOnOpen && _sync2DMapToStreaming3D()) {
                _streamingNeedsMapSyncOnOpen = false
            }
            if (streaming3DLoader.status === Loader.Ready &&
                    streaming3DLoader.item &&
                    typeof streaming3DLoader.item.activate === "function") {
                streaming3DLoader.item.activate()
            }
        } else {
            _setStreamingActive(false)
            _setLegacyActive(true)
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

    // If streaming flag flips while open, swap implementations immediately
    on_Streaming3DEnabledChanged: {
        if (!isOpen) {
            return
        }

        console.log("[Viewer3D] streaming flag changed ->", _streaming3DEnabled)

        if (_streaming3DEnabled === true) {
            _setLegacyActive(false)
            _setStreamingActive(true)
            if (_streamingNeedsMapSyncOnOpen && _sync2DMapToStreaming3D()) {
                _streamingNeedsMapSyncOnOpen = false
            }
        } else {
            _setStreamingActive(false)
            _setLegacyActive(true)
        }
    }

    // -----------------------------
    // Legacy (OSM) viewer path
    // -----------------------------
    Component {
        id: viewer3DManagerComponent

        Viewer3DManager {
            id: _viewer3DManager
        }
    }

    Loader {
        id: view3DManagerLoader
        active: false
        sourceComponent: viewer3DManagerComponent

        onLoaded: {
            // Only proceed if legacy path is active
            if (_streaming3DEnabled !== true) {
                view3DLoader.active = true
            }
        }
    }

    Loader {
        id: view3DLoader
        anchors.fill: parent
        active: false
        source: "Models3D/Viewer3DModel.qml"

        onLoaded: {
            item.viewer3DManager = view3DManagerLoader.item
        }
    }

    Binding {
        target: view3DLoader.item
        property: "isViewer3DOpen"
        value: isOpen
        when: (_streaming3DEnabled !== true) && (view3DLoader.status === Loader.Ready)
    }

    // -----------------------------
    // Streaming viewer path
    // -----------------------------
    Loader {
        id: streaming3DLoader
        anchors.fill: parent
        active: false

        // Must be in the same folder as this file
        source: "Viewer3DStreaming.qml"

        onStatusChanged: {
            if (status === Loader.Loading) {
                _streamingLoadError = ""
            } else if (status === Loader.Error) {
                // Show actual failure reason (very helpful)
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
